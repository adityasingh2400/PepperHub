import { createClient } from "jsr:@supabase/supabase-js@2";

const COMPOUNDS = [
  { name: "Ipamorelin",       slug: "ipamorelin",       fda_status: "research" },
  { name: "CJC-1295",         slug: "cjc-1295",         fda_status: "research" },
  { name: "BPC-157",          slug: "bpc-157",          fda_status: "research" },
  { name: "TB-500",           slug: "tb-500",           fda_status: "research" },
  { name: "GHK-Cu",           slug: "ghk-cu",           fda_status: "research" },
  { name: "Semaglutide",      slug: "semaglutide",      fda_status: "approved" },
  { name: "Tirzepatide",      slug: "tirzepatide",      fda_status: "approved" },
  { name: "DSIP",             slug: "dsip",             fda_status: "research" },
  { name: "Selank",           slug: "selank",           fda_status: "research" },
  { name: "Semax",            slug: "semax",            fda_status: "research" },
  { name: "PT-141",           slug: "pt-141",           fda_status: "approved" },
  { name: "Epithalon",        slug: "epithalon",        fda_status: "research" },
  { name: "Hexarelin",        slug: "hexarelin",        fda_status: "research" },
  { name: "GHRP-6",           slug: "ghrp-6",           fda_status: "research" },
  { name: "Tesamorelin",      slug: "tesamorelin",      fda_status: "approved" },
  { name: "AOD-9604",         slug: "aod-9604",         fda_status: "research" },
  { name: "IGF-1 LR3",        slug: "igf-1-lr3",        fda_status: "research" },
  { name: "Thymosin Alpha-1", slug: "thymosin-alpha-1", fda_status: "research" },
  { name: "MGF",              slug: "mgf",              fda_status: "research" },
  { name: "Cerebrolysin",     slug: "cerebrolysin",     fda_status: "grey"     },
];

async function synthesizeWithClaude(compound: string, apiKey: string) {
  const prompt = `You are a knowledgeable researcher synthesizing everything known about the peptide "${compound}" — from clinical research, biohacking communities, forums like r/Peptides, and real-world user experience.

Generate a structured profile for "${compound}".

Respond with a JSON object with exactly these fields:
{
  "summary": "2-3 sentence overview of what this peptide does and why people use it",
  "benefits": ["array of up to 6 reported benefits, specific and concrete"],
  "side_effects": ["array of up to 6 reported side effects, honest including rare ones"],
  "dosing_low_mcg": number or null,
  "dosing_high_mcg": number or null,
  "half_life_hrs": number or null,
  "stacking_notes": "most common stacks and why, or empty string if none well established",
  "community_summary": "2-3 sentences on lived experience — what users actually notice, realistic timelines, honest take on what works and what is overhyped"
}

Respond with raw JSON only, no markdown, no explanation.`;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 1024,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Claude ${res.status}: ${body}`);
  }

  const data = await res.json();
  const raw = data.content?.[0]?.text ?? "{}";
  // Strip markdown code fences if present
  const text = raw.replace(/^```(?:json)?\n?/, "").replace(/\n?```$/, "").trim();
  return JSON.parse(text);
}

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (!authHeader || authHeader !== `Bearer ${serviceRoleKey}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    serviceRoleKey
  );
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY")!;

  if (!anthropicKey) {
    return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY not set" }), { status: 500 });
  }

  const results: { compound: string; status: string; error?: string }[] = [];

  for (const compound of COMPOUNDS) {
    try {
      const synthesis = await synthesizeWithClaude(compound.name, anthropicKey);

      const { error } = await supabase.from("compounds").upsert(
        {
          name: compound.name,
          slug: compound.slug,
          fda_status: compound.fda_status,
          summary_md: synthesis.summary,
          benefits: synthesis.benefits,
          side_effects: synthesis.side_effects,
          dosing_range_low_mcg: synthesis.dosing_low_mcg,
          dosing_range_high_mcg: synthesis.dosing_high_mcg,
          half_life_hrs: synthesis.half_life_hrs,
          stacking_notes: synthesis.stacking_notes,
          community_summary: synthesis.community_summary,
          post_count: 0,
          last_synced_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        },
        { onConflict: "slug" }
      );

      if (error) throw new Error(`DB: ${error.message}`);
      results.push({ compound: compound.name, status: "ok" });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      results.push({ compound: compound.name, status: "error", error: msg });
    }
  }

  return new Response(JSON.stringify({ synced: results }, null, 2), {
    headers: { "Content-Type": "application/json" },
  });
});
