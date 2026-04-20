create table if not exists compounds (
  id uuid default gen_random_uuid() primary key,
  name text not null unique,
  slug text not null unique,
  half_life_hrs numeric,
  dosing_range_low_mcg int,
  dosing_range_high_mcg int,
  benefits text[] default '{}',
  side_effects text[] default '{}',
  stacking_notes text,
  fda_status text default 'research' check (fda_status in ('research','grey','approved')),
  summary_md text,
  community_summary text,  -- synthesized from Reddit/forum data
  post_count int default 0, -- number of Reddit posts used for last synthesis
  last_synced_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Public read access, no user writes
alter table compounds enable row level security;

create policy "Anyone can read compounds"
  on compounds for select
  using (true);
