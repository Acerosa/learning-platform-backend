# Operational scripts

## Pages deployment health

Fleet config: `pages-health-targets.json`.

```bash
LP_SUPABASE_PUBLISHABLE_KEY=sb_publishable_... npm run check:pages-health
node scripts/ops/run-pages-health.mjs --require-browser
```

Scheduled workflow: `.github/workflows/pages-health.yml`.

## Curriculum / marking diagnostics (staff-only)

```bash
LP_SUPABASE_URL=https://hubwpkrqndorznwzvaer.supabase.co \
LP_SUPABASE_PUBLISHABLE_KEY=... \
LP_STAFF_ACCESS_TOKEN=... \
npm run check:curriculum-marking-health
```

Reads staff `admin_api` views only (no answer keys). Keep anon statement timeout unchanged when investigating timeouts.
