import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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

    const { data: profile } = await supabase
      .from("users_profiles")
      .select("*")
      .eq("user_id", user.id)
      .single();

    if (!profile) {
      return new Response(JSON.stringify({ error: "no_profile" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: protocols } = await supabase
      .from("user_protocols")
      .select("id")
      .eq("user_id", user.id)
      .eq("is_active", true)
      .limit(1);

    const planDate = new Date().toISOString().split("T")[0];
    const timezone = profile.timezone ?? "America/New_York";

    let activeCompounds: string[] = [];
    let mealWindows: object[] = [];

    if (protocols && protocols.length > 0) {
      const protocolId = protocols[0].id;

      const { data: compounds } = await supabase
        .from("protocol_compounds")
        .select("compound_name, dose_mcg, dose_times, frequency")
        .eq("protocol_id", protocolId);

      if (compounds && compounds.length > 0) {
        activeCompounds = compounds.map((c: { compound_name: string }) => c.compound_name);

        const compoundNames = activeCompounds;
        const { data: rules } = await supabase
          .from("peptide_timing_rules")
          .select("*")
          .in("compound_name", compoundNames);

        const ruleMap = Object.fromEntries(
          (rules ?? []).map((r: { compound_name: string }) => [r.compound_name, r])
        );

        // Build simple meal windows
        const todayDoses: { compound: string; time: string; preMins: number; postMins: number; carbLimit: number | null }[] = [];
        for (const compound of compounds) {
          const rule = ruleMap[compound.compound_name];
          for (const t of (compound.dose_times ?? [])) {
            todayDoses.push({
              compound: compound.compound_name,
              time: t,
              preMins: rule?.pre_dose_window_mins ?? 0,
              postMins: rule?.post_dose_window_mins ?? 0,
              carbLimit: rule?.carb_limit_g ?? null,
            });
          }
        }

        todayDoses.sort((a, b) => a.time.localeCompare(b.time));

        if (todayDoses.length > 0) {
          mealWindows = todayDoses.flatMap((dose) => {
            const windows = [];
            if (dose.preMins > 0) {
              windows.push({
                type: "pre_dose",
                label: "Pre-dose (restricted)",
                compound: dose.compound,
                dose_time: dose.time,
                pre_window_mins: dose.preMins,
                restricted: true,
                carb_limit_g: dose.carbLimit,
              });
            }
            if (dose.postMins > 0) {
              windows.push({
                type: "post_dose",
                label: "Post-dose (restricted)",
                compound: dose.compound,
                dose_time: dose.time,
                post_window_mins: dose.postMins,
                restricted: true,
                carb_limit_g: dose.carbLimit,
              });
            }
            return windows;
          });
        }
      }
    }

    const payload = {
      plan_date: planDate,
      tdee_kcal: profile.tdee_kcal,
      goal: profile.goal,
      active_compounds: activeCompounds,
      meal_windows: mealWindows,
      daily_totals: {
        protein_g: profile.macro_goal_protein_g,
        carbs_g: profile.macro_goal_carbs_g,
        fat_g: profile.macro_goal_fat_g,
        kcal: Math.round(profile.macro_goal_protein_g * 4 + profile.macro_goal_carbs_g * 4 + profile.macro_goal_fat_g * 9),
      },
    };

    // Upsert with optimistic concurrency
    await supabase.from("partition_plan_cache").upsert(
      { user_id: user.id, plan_date: planDate, payload, updated_at: new Date().toISOString() },
      { onConflict: "user_id,plan_date" }
    );

    return new Response(JSON.stringify(payload), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
