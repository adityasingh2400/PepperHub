create table if not exists users_profiles (
  id         uuid default gen_random_uuid() primary key,
  user_id    uuid references auth.users(id) on delete cascade not null unique,
  display_name text,
  weight_kg  numeric,
  height_cm  numeric,
  age_years  int,
  biological_sex text check (biological_sex in ('male','female','other')),
  activity_level text check (activity_level in ('sedentary','light','moderate','active','very_active')),
  goal       text check (goal in ('recomp','bulk','cut')),
  rmr_kcal   numeric,
  tdee_kcal  numeric,
  macro_goal_mode text default 'auto' check (macro_goal_mode in ('auto','custom')),
  macro_goal_protein_g int,
  macro_goal_carbs_g   int,
  macro_goal_fat_g     int,
  timezone   text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table users_profiles enable row level security;

create policy "Users can read own profile"
  on users_profiles for select
  using (auth.uid() = user_id);

create policy "Users can insert own profile"
  on users_profiles for insert
  with check (auth.uid() = user_id);

create policy "Users can update own profile"
  on users_profiles for update
  using (auth.uid() = user_id);
