# Pepper data + seed scripts

← Back to the main project: **[README.md](../README.md)**

One-shot scripts for populating the Pepper Supabase project.

## Prereqs

- [Bun](https://bun.sh) ≥ 1.1
- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in your shell (NOT the anon key)
- The matching SQL migration applied (`supabase db push` or via dashboard)

## Scripts

### `seed_compound_metadata.ts`

Loads `data/compound_metadata.yaml` and upserts the 24-compound starter
catalog into `compounds` + `compound_pin_sites`.

```bash
bun scripts/seed_compound_metadata.ts             # dry run
bun scripts/seed_compound_metadata.ts --apply     # write
```

### `seed_citations.ts` (TODO)

Pulls peer-reviewed sources from PubMed for each compound + topic and writes
them to `citations`.

### `generate_veo_videos.ts`

Renders the instructional injection videos (defined in `data/veo_prompts.yaml`)
using Vertex AI Veo 2 and uploads them to Supabase Storage. Idempotent —
re-runs skip videos that are already in the bucket.

```bash
GCP_PROJECT_ID=oriqprod \
GCP_LOCATION=us-central1 \
GCP_SERVICE_ACCOUNT_KEY=path/to/key.json \
SUPABASE_URL=https://<project>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=eyJ... \
bun scripts/generate_veo_videos.ts --dry-run    # validate prompts only
bun scripts/generate_veo_videos.ts              # actually generate + upload
```

Produces a per-run cost report in `data/veo_runs.json`.

### `seed_citations.ts` (TODO)

Pulls peer-reviewed sources from PubMed for each compound + topic and writes
them to `citations`.
