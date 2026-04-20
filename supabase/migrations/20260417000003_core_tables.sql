-- Core v1.0 tables

-- user_protocols
CREATE TABLE IF NOT EXISTS user_protocols (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    name text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    start_date date DEFAULT CURRENT_DATE NOT NULL,
    end_date date,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE user_protocols ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own protocols" ON user_protocols FOR ALL USING (auth.uid() = user_id);

-- protocol_compounds
CREATE TABLE IF NOT EXISTS protocol_compounds (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    protocol_id uuid REFERENCES user_protocols(id) ON DELETE CASCADE NOT NULL,
    compound_id uuid REFERENCES compounds(id),
    compound_name text NOT NULL,
    dose_mcg numeric NOT NULL,
    frequency text NOT NULL DEFAULT 'daily',
    dose_times time[] NOT NULL DEFAULT '{}',
    custom_days int[] DEFAULT '{}',
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE protocol_compounds ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own protocol compounds" ON protocol_compounds
    FOR ALL USING (EXISTS (
        SELECT 1 FROM user_protocols WHERE id = protocol_compounds.protocol_id AND user_id = auth.uid()
    ));

-- vials
CREATE TABLE IF NOT EXISTS vials (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    compound_name text NOT NULL,
    total_mg numeric NOT NULL,
    bac_water_ml numeric NOT NULL,
    concentration_mcg_per_unit numeric NOT NULL,
    units_remaining numeric NOT NULL,
    purchased_at date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE vials ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own vials" ON vials FOR ALL USING (auth.uid() = user_id);

-- dose_logs
CREATE TABLE IF NOT EXISTS dose_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    compound_name text NOT NULL,
    protocol_id uuid REFERENCES user_protocols(id) ON DELETE SET NULL,
    dosed_at timestamptz DEFAULT now() NOT NULL,
    dose_mcg numeric NOT NULL,
    injection_site text DEFAULT '' NOT NULL,
    vial_id uuid REFERENCES vials(id) ON DELETE SET NULL,
    notes text DEFAULT '' NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    synced_at timestamptz
);
ALTER TABLE dose_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own dose logs" ON dose_logs FOR ALL USING (auth.uid() = user_id);

-- food_logs
CREATE TABLE IF NOT EXISTS food_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    logged_at timestamptz DEFAULT now() NOT NULL,
    food_name text NOT NULL,
    barcode text,
    kcal int NOT NULL,
    protein_g numeric NOT NULL,
    carbs_g numeric NOT NULL,
    fat_g numeric NOT NULL,
    fiber_g numeric,
    sugar_g numeric,
    sat_fat_g numeric,
    sodium_mg numeric,
    source text NOT NULL DEFAULT 'manual',
    meal_window text NOT NULL DEFAULT 'free',
    serving_qty numeric NOT NULL DEFAULT 1,
    serving_unit text DEFAULT '',
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    synced_at timestamptz
);
ALTER TABLE food_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own food logs" ON food_logs FOR ALL USING (auth.uid() = user_id);

-- side_effect_logs
CREATE TABLE IF NOT EXISTS side_effect_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    logged_at timestamptz DEFAULT now() NOT NULL,
    symptom text NOT NULL,
    severity smallint NOT NULL CHECK (severity BETWEEN 1 AND 5),
    notes text DEFAULT '' NOT NULL,
    linked_dose_id uuid REFERENCES dose_logs(id) ON DELETE SET NULL,
    linked_compound_name text,
    auto_linked boolean DEFAULT false NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    synced_at timestamptz
);
ALTER TABLE side_effect_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own side effect logs" ON side_effect_logs FOR ALL USING (auth.uid() = user_id);

-- peptide_timing_rules (public read, admin write)
CREATE TABLE IF NOT EXISTS peptide_timing_rules (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    compound_name text NOT NULL UNIQUE,
    pre_dose_window_mins int,
    post_dose_window_mins int,
    carb_limit_g int,
    fat_limit_g int,
    warning_text text,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE peptide_timing_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read timing rules" ON peptide_timing_rules FOR SELECT USING (true);

-- partition_plan_cache
CREATE TABLE IF NOT EXISTS partition_plan_cache (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    plan_date date NOT NULL,
    payload jsonb NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    UNIQUE (user_id, plan_date)
);
ALTER TABLE partition_plan_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own partition plan cache" ON partition_plan_cache FOR ALL USING (auth.uid() = user_id);

-- Seed timing rules for top compounds
INSERT INTO peptide_timing_rules (compound_name, pre_dose_window_mins, post_dose_window_mins, carb_limit_g, fat_limit_g, warning_text)
VALUES
    ('Ipamorelin',   45, 90,  0,    NULL, 'Ipamorelin: avoid carbs for 45 min pre-dose and 90 min post-dose'),
    ('CJC-1295',     60, 120, 0,    NULL, 'CJC-1295: avoid carbs for 60 min pre-dose and 2 hrs post-dose'),
    ('GHRP-6',       30, 60,  0,    NULL, 'GHRP-6: avoid carbs/fat 30 min pre-dose and 60 min post-dose'),
    ('GHRP-2',       30, 60,  0,    NULL, 'GHRP-2: avoid carbs 30 min pre-dose and 60 min post-dose'),
    ('MK-677',       NULL, NULL, NULL, NULL, NULL),
    ('BPC-157',      NULL, NULL, NULL, NULL, NULL),
    ('TB-500',       NULL, NULL, NULL, NULL, NULL),
    ('GHK-Cu',       NULL, NULL, NULL, NULL, NULL),
    ('Semaglutide',  NULL, NULL, NULL, NULL, NULL),
    ('Tirzepatide',  NULL, NULL, NULL, NULL, NULL)
ON CONFLICT (compound_name) DO NOTHING;
