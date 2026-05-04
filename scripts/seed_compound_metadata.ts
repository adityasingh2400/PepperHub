// Seed Supabase `compounds` (and `compound_pin_sites`) from data/compound_metadata.yaml.
//
// Usage:
//   bun scripts/seed_compound_metadata.ts                  # dry-run
//   bun scripts/seed_compound_metadata.ts --apply          # write to Supabase
//
// Env vars required for --apply:
//   SUPABASE_URL              e.g. https://<your-project-ref>.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY service role key (NOT the anon key)
//
// What it does:
//   1. Parses data/compound_metadata.yaml
//   2. Upserts each compound by `slug` into `compounds`
//   3. Replaces compound_pin_sites rows for each compound with the new
//      preference list (preference 0 = primary)
//   4. Prints a diff summary
//
// Safe to re-run. The migration `20260421000001_compound_metadata_v2.sql` MUST
// be applied before the first run.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parse as parseYaml } from "yaml";

type Compound = {
  slug: string;
  name: string;
  half_life_hrs?: number | null;
  dosing_range_low_mcg?: number | null;
  dosing_range_high_mcg?: number | null;
  benefits?: string[];
  side_effects?: string[];
  stacking_notes?: string | null;
  fda_status?: "research" | "grey" | "approved";
  summary_md?: string | null;
  goal_categories?: string[];
  administration_routes?: string[];
  time_to_effect_hours?: number | null;
  peak_effect_hours?: number | null;
  duration_hours?: number | null;
  dosing_formula?: string | null;
  dosing_unit?: string | null;
  dosing_frequency?: string | null;
  bac_water_ml_default?: number | null;
  storage_temp?: string | null;
  storage_max_days?: number | null;
  needle_gauge_default?: string | null;
  needle_length_default?: string | null;
  recommended_site_ids?: string[];
};

const APPLY = process.argv.includes("--apply");
const YAML_PATH = resolve(import.meta.dir, "..", "data", "compound_metadata.yaml");
const SUPABASE_URL = process.env.SUPABASE_URL ?? "";
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";

function loadYaml(): Compound[] {
  const text = readFileSync(YAML_PATH, "utf8");
  const doc = parseYaml(text) as { compounds: Compound[] };
  if (!doc?.compounds || !Array.isArray(doc.compounds)) {
    throw new Error("Invalid compound_metadata.yaml: missing `compounds:` array");
  }
  return doc.compounds;
}

async function supabaseFetch<T = unknown>(
  path: string,
  init: RequestInit & { headers?: Record<string, string> } = {},
): Promise<T> {
  if (!SUPABASE_URL || !SERVICE_ROLE) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for --apply");
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_ROLE,
      Authorization: `Bearer ${SERVICE_ROLE}`,
      "Content-Type": "application/json",
      Prefer: "return=representation,resolution=merge-duplicates",
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Supabase ${path} failed: ${res.status} ${body}`);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

async function upsertCompound(c: Compound): Promise<{ id: string }> {
  const row = {
    slug: c.slug,
    name: c.name,
    half_life_hrs: c.half_life_hrs ?? null,
    dosing_range_low_mcg: c.dosing_range_low_mcg ?? null,
    dosing_range_high_mcg: c.dosing_range_high_mcg ?? null,
    benefits: c.benefits ?? [],
    side_effects: c.side_effects ?? [],
    stacking_notes: c.stacking_notes ?? null,
    fda_status: c.fda_status ?? "research",
    summary_md: c.summary_md ?? null,
    goal_categories: c.goal_categories ?? [],
    administration_routes: c.administration_routes ?? ["subq"],
    time_to_effect_hours: c.time_to_effect_hours ?? null,
    peak_effect_hours: c.peak_effect_hours ?? null,
    duration_hours: c.duration_hours ?? null,
    dosing_formula: c.dosing_formula ?? null,
    dosing_unit: c.dosing_unit ?? "mcg",
    dosing_frequency: c.dosing_frequency ?? "daily",
    bac_water_ml_default: c.bac_water_ml_default ?? 2.0,
    storage_temp: c.storage_temp ?? "refrigerated",
    storage_max_days: c.storage_max_days ?? 30,
    needle_gauge_default: c.needle_gauge_default ?? "29G",
    needle_length_default: c.needle_length_default ?? "1/2 inch",
  };
  const result = await supabaseFetch<Array<{ id: string }>>(
    "/compounds?on_conflict=slug",
    { method: "POST", body: JSON.stringify(row) },
  );
  if (!result?.[0]?.id) throw new Error(`upsert returned no id for ${c.slug}`);
  return { id: result[0].id };
}

async function replacePinRecommendations(compoundId: string, siteIds: string[]) {
  await supabaseFetch(`/compound_pin_sites?compound_id=eq.${compoundId}`, {
    method: "DELETE",
    headers: { Prefer: "return=minimal" },
  });
  if (siteIds.length === 0) return;
  const rows = siteIds.map((id, idx) => ({
    compound_id: compoundId,
    pin_site_id: id,
    preference: idx,
  }));
  await supabaseFetch("/compound_pin_sites", {
    method: "POST",
    body: JSON.stringify(rows),
    headers: { Prefer: "return=minimal" },
  });
}

async function main() {
  const compounds = loadYaml();
  console.log(`Loaded ${compounds.length} compounds from ${YAML_PATH}`);

  if (!APPLY) {
    console.log(`\n[dry-run] Would upsert ${compounds.length} compounds.`);
    for (const c of compounds.slice(0, 5)) {
      console.log(`  - ${c.slug.padEnd(20)} routes=${(c.administration_routes ?? []).join(",")} sites=${(c.recommended_site_ids ?? []).length}`);
    }
    console.log("  ...");
    console.log("\nRun with --apply to write to Supabase.");
    return;
  }

  let written = 0;
  for (const c of compounds) {
    const { id } = await upsertCompound(c);
    await replacePinRecommendations(id, c.recommended_site_ids ?? []);
    written += 1;
    process.stdout.write(`  ✓ ${c.slug}${written < compounds.length ? "\n" : "\n"}`);
  }
  console.log(`\n✓ Wrote ${written} compounds + pin recommendations to Supabase.`);
}

main().catch((err) => {
  console.error("Seed failed:", err);
  process.exit(1);
});
