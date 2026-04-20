-- workouts table
CREATE TABLE IF NOT EXISTS workouts (
    id uuid PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    logged_at timestamptz NOT NULL,
    type text NOT NULL,
    duration_minutes int NOT NULL,
    notes text NOT NULL DEFAULT '',
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE workouts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own workouts" ON workouts FOR ALL USING (auth.uid() = user_id);

-- Fix protocol_compounds.dose_times: time[] → jsonb (client stores JSON arrays)
ALTER TABLE protocol_compounds
    ALTER COLUMN dose_times TYPE jsonb
    USING '[]'::jsonb;
ALTER TABLE protocol_compounds
    ALTER COLUMN dose_times SET DEFAULT '[]';

-- Fix goal constraint to include anti_aging
ALTER TABLE users_profiles DROP CONSTRAINT IF EXISTS users_profiles_goal_check;
ALTER TABLE users_profiles ADD CONSTRAINT users_profiles_goal_check
    CHECK (goal IN ('recomp','bulk','cut','anti_aging'));

-- Add missing extended profile columns (idempotent)
ALTER TABLE users_profiles ADD COLUMN IF NOT EXISTS experience text;
ALTER TABLE users_profiles ADD COLUMN IF NOT EXISTS training_days_per_week int;
ALTER TABLE users_profiles ADD COLUMN IF NOT EXISTS eating_style text;
ALTER TABLE users_profiles ADD COLUMN IF NOT EXISTS has_protocol boolean;
ALTER TABLE users_profiles ADD COLUMN IF NOT EXISTS protocol_compounds text[];
ALTER TABLE users_profiles ADD COLUMN IF NOT EXISTS calorie_target_kcal numeric;
