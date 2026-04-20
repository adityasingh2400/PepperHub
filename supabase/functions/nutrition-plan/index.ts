import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface UserProfile {
  goal: string;
  experience: string;
  biologicalSex: string;
  age: number;
  heightCm: number;
  weightKg: number;
  activityLevel: string;
  trainingDaysPerWeek: number;
  trainingTime: string;
  eatingStyle: string;
  mealsPerDay: number;
  hasProtocol: boolean;
  compounds: string[];
  baselineCalories: number;
  baselineProteinG: number;
  baselineCarbsG: number;
  baselineFatG: number;
}

interface NutritionPlan {
  calories: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  overallRationale: string;
  caloriesExplanation: string;
  proteinExplanation: string;
  carbsExplanation: string;
  fatExplanation: string;
}

function clamp(val: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, val));
}

function validatePlan(plan: NutritionPlan, profile: UserProfile): NutritionPlan {
  return {
    ...plan,
    calories: clamp(plan.calories, 1200, 5000),
    proteinG: clamp(plan.proteinG, Math.round(profile.weightKg * 1.4), Math.round(profile.weightKg * 3.8)),
    carbsG: clamp(plan.carbsG, 30, 700),
    fatG: clamp(plan.fatG, Math.round(profile.weightKg * 0.4), Math.round(profile.weightKg * 2.2)),
  };
}

// Per-compound nutritional guidance — only injected when user actually selected the compound
const COMPOUND_GUIDANCE: Record<string, string> = {
  "BPC-157": "Accelerates collagen synthesis and tissue repair. Protein consumed within 2 hours of dosing is more efficiently utilized. Target 2.6–3.2g protein/kg to fully activate the healing cascade.",
  "TB-500": "Promotes actin binding and satellite cell activation. Elevated protein turnover means daily protein requirements are higher than standard. Anti-inflammatory fats (omega-3s) support its mechanism — don't cut fat too low.",
  "CJC-1295": "Raises endogenous GH/IGF-1. A high-protein diet (2.5–3g/kg) significantly amplifies the anabolic response. Carbohydrates blunt the GH pulse — time carb-heavy meals away from injection windows.",
  "Ipamorelin": "GHRH secretagogue — same GH-pulse logic as CJC-1295. Higher protein utilization. Keep carbs lower around dose timing.",
  "GHRP-2": "Strong GH releaser with ghrelin mimicry — increases appetite. Protein priority is critical to prevent fat gain from elevated hunger. High-protein meals blunt the ghrelin-driven overconsumption.",
  "GHRP-6": "Similar to GHRP-2 with stronger appetite stimulation. Aggressive protein targets (2.8–3.2g/kg) are essential. Be deliberate about total calorie control given increased hunger.",
  "Sermorelin": "Gentle GHRH analog. Moderate protein increase above baseline (2.2–2.6g/kg) is sufficient. Supports body recomposition goals when combined with training.",
  "Tesamorelin": "Reduces visceral fat via GH stimulation. Works synergistically with a mild caloric deficit. Maintain protein to preserve lean mass during fat mobilization.",
  "AOD-9604": "Fat mobilization fragment of GH. Works best with a mild caloric deficit. No special macro adjustments needed — focus on overall calorie control and adequate protein.",
  "Semaglutide": "GLP-1 agonist — suppresses appetite and slows gastric emptying. CRITICAL: must maintain aggressive protein targets (2.4–3g/kg) despite reduced appetite to prevent muscle loss. Every meal must lead with protein.",
  "Tirzepatide": "Dual GIP/GLP-1 agonist — stronger appetite suppression than semaglutide alone. Same protein-preservation imperative. Risk of muscle loss is real at low intake. Protein minimum is non-negotiable.",
  "PT-141": "Sexual health peptide. No direct nutritional interaction — macros are set by other profile factors.",
  "Melanotan II": "Causes appetite suppression similar to GLP-1s. Ensure adequate protein intake despite reduced hunger. Protein-first meal structure helps.",
  "Thymosin Alpha-1": "Immune modulator. Anti-inflammatory dietary pattern supports its mechanism — prioritize omega-3-rich fat sources. No major macro shifts required.",
  "GHK-Cu": "Copper peptide for skin, repair, and anti-aging. Anti-inflammatory fats and adequate protein support tissue remodeling. No major macro adjustments.",
  "MK-677": "Oral GH secretagogue with strong appetite stimulation. Similar to GHRP-6 — high protein is essential to prevent fat gain from increased hunger. Track calories carefully.",
  "Hexarelin": "Potent GHRP. Elevated protein needs similar to GHRP-2/6. Carb timing around GH pulse matters.",
  "Selank": "Anxiolytic/nootropic peptide. No direct nutritional interaction.",
  "Semax": "Nootropic peptide. No direct nutritional interaction. Adequate omega-3 fats support neurological effects.",
};

function compoundGuidance(compounds: string[]): string {
  return compounds
    .filter((c) => COMPOUND_GUIDANCE[c])
    .map((c) => `- ${c}: ${COMPOUND_GUIDANCE[c]}`)
    .join("\n");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response("Unauthorized", { status: 401 });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return new Response("Unauthorized", { status: 401 });

    const profile: UserProfile = await req.json();

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY not configured");

    const prompt = buildPrompt(profile);

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!anthropicRes.ok) {
      const err = await anthropicRes.text();
      throw new Error(`Anthropic API error: ${err}`);
    }

    const anthropicData = await anthropicRes.json();
    const rawText: string = anthropicData.content[0].text;

    const jsonMatch = rawText.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error("No JSON in response");

    const parsed: NutritionPlan = JSON.parse(jsonMatch[0]);
    const validated = validatePlan(parsed, profile);

    return new Response(JSON.stringify(validated), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

function buildPrompt(p: UserProfile): string {
  const bmi = p.weightKg / Math.pow(p.heightCm / 100, 2);
  const lbm = p.weightKg * (1 - (bmi > 25 ? 0.22 : 0.18));
  const hasCompounds = p.compounds && p.compounds.length > 0;

  const protocolSection = !p.hasProtocol
    ? ""
    : hasCompounds
    ? `PEPTIDE PROTOCOL — USER'S CONFIRMED COMPOUNDS:
The user is currently taking: ${p.compounds.join(", ")}

Specific nutritional implications for their stack:
${compoundGuidance(p.compounds)}

Adjust macros based ONLY on these compounds. Do NOT reference or assume any compounds the user did not list. Your explanations must name the actual compounds they are taking.`
    : `PEPTIDE PROTOCOL:
The user is on a protocol but hasn't specified compounds. Apply a conservative protein increase (~10-15% above baseline) and note in the explanation that compound-specific tuning can happen once their stack is known.`;

  return `You are a precision nutrition coach specializing in peptide-enhanced performance. Create a personalized daily nutrition plan for this user.

USER PROFILE:
- Goal: ${p.goal} (${goalDescription(p.goal)})
- Training experience: ${p.experience}
- Biological sex: ${p.biologicalSex}
- Age: ${p.age} years
- Height: ${p.heightCm} cm | Weight: ${p.weightKg} kg | BMI: ${bmi.toFixed(1)}
- Estimated lean body mass: ~${lbm.toFixed(1)} kg
- Activity level: ${p.activityLevel}
- Training days/week: ${p.trainingDaysPerWeek}
- Preferred training time: ${p.trainingTime}
- Eating style: ${p.eatingStyle}
- Meals per day: ${p.mealsPerDay}
- On a peptide protocol: ${p.hasProtocol ? "YES" : "No"}

FORMULA BASELINE (Mifflin-St Jeor):
- Baseline calories: ${p.baselineCalories} kcal
- Baseline protein: ${p.baselineProteinG}g
- Baseline carbs: ${p.baselineCarbsG}g
- Baseline fat: ${p.baselineFatG}g

${protocolSection}

YOUR TASK:
1. Start from the formula baseline and adjust based on the full profile
2. ${hasCompounds ? "Adjust macros specifically for the compounds listed above — especially protein" : "Set protein appropriate for goal and experience level"}
3. Ensure macros are internally consistent: calories ≈ protein×4 + carbs×4 + fat×9
4. Write explanations SPECIFIC to this person — reference their actual compounds by name, their goal, their training days. No generic advice.
5. Keep explanations to 1-2 sentences each, direct and actionable.

RESPOND WITH ONLY THIS JSON:
{
  "calories": <integer>,
  "proteinG": <integer>,
  "carbsG": <integer>,
  "fatG": <integer>,
  "overallRationale": "<2-3 sentences summarizing the plan and why it fits this person>",
  "caloriesExplanation": "<1-2 sentences on this calorie target>",
  "proteinExplanation": "<1-2 sentences on this protein target — name their compounds if applicable>",
  "carbsExplanation": "<1-2 sentences on this carb target>",
  "fatExplanation": "<1-2 sentences on this fat target>"
}`;
}

function goalDescription(goal: string): string {
  switch (goal) {
    case "Recomp": return "build muscle while losing fat";
    case "Bulk": return "maximize muscle gain with controlled surplus";
    case "Cut": return "aggressive fat loss while preserving lean mass";
    case "Anti-aging": return "longevity and hormonal optimization";
    default: return goal;
  }
}
