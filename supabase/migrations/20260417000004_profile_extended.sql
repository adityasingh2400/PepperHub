-- Extend users_profiles with onboarding fields missing from v1

-- Fix goal constraint to include anti_aging
alter table users_profiles drop constraint if exists users_profiles_goal_check;
alter table users_profiles add constraint users_profiles_goal_check
  check (goal in ('recomp','bulk','cut','anti_aging'));

-- New columns
alter table users_profiles
  add column if not exists experience            text check (experience in ('new','some','veteran')),
  add column if not exists training_days_per_week int check (training_days_per_week between 0 and 7),
  add column if not exists eating_style          text check (eating_style in ('standard','low_carb','high_carb','intermittent_fasting')),
  add column if not exists has_protocol          boolean default false,
  add column if not exists protocol_compounds    text[],
  add column if not exists calorie_target_kcal   numeric;  -- AI-adjusted target (tdee_kcal stays as maintenance)
