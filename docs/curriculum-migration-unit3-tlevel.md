# Unit 3 and T Level curriculum migration

This document records the static-to-database curriculum migration for **Unit 3
Cyber Security** and **T Level Digital Software Development**. It complements
`docs/content-publication.md` and Core `docs/curriculum-runtime.md`.

## Status (hosted 2026-08-18)

| Hub | hubCode | courseKey | Hosted publication | Runtime wiring | Classification |
| --- | --- | --- | --- | --- | --- |
| Unit 3 Cyber Security | `unit-3-cyber-security` | `ocr-level-3-it` | current `0.2.1` (`0.2.0` superseded) | `platform.curriculum.loadLatest()` | **DATABASE_DRIVEN** |
| T Level Software Development | `tlevel-software-development` | `t-level-digital-software-development` | current `0.2.2` (first hosted package `0.2.1` superseded) | `platform.curriculum.loadLatest()` | **DATABASE_DRIVEN** |
| Unit 14 (reference) | `unit-14-software-engineering-for-business` | `ocr-level-3-it` | `0.2.2` | unchanged | **DATABASE_DRIVEN** |

Hosted verification: both learner hubs loaded `api.published_curriculum_package`
with `data-curriculum-source=published`. Admin edited a field and republished
without a Git commit, GitHub Action or Pages deploy. Git/static fallback was
not used while a publication existed.

## Architecture after migration

```
Admin Portal
    ↓ draft / edit / publish (admin_api.publish_curriculum)
Supabase platform.curriculum_publications
    ↓ api.published_curriculum_package(hub, course, version?)
@learning-platform/core/curriculum-runtime
    ↓ platform.curriculum.loadLatest()
Unit 3 / T Level / Unit 14 learner hubs
```

Hubs provide identity only (`hubCode`, `courseKey`). They do not implement
publication lookup, cache keys or schema validation.

## Static sources converted

### Unit 3

| Aspect | Source |
| --- | --- |
| Weeks | `week-{1–7}/` hub pages + `js/course-context.js` registry |
| Sessions | One session per registered activity route |
| Activities | `week-{2–7}/data/*.js` (80 files) + Week 1 catalogue ids from delivery manifest |
| Questions/blocks | Per-activity JS objects (OCR-style, retrieval, practical, peer marking) |
| Renderer | Existing `app.js` / React activity shells (application code) |
| Identity | `hubCode=unit-3-cyber-security`, `courseKey=ocr-level-3-it` |

**Week 1 gap:** teaching copy for several Week 1 activities still lives only in
legacy Apps Script. The converted package includes scaffolding reflection blocks
for those ids so the package validates; full Week 1 DATABASE_DRIVEN delivery
requires extracting that copy into Admin.

### T Level

| Aspect | Source |
| --- | --- |
| Weeks | Single canonical week `foundations` (Foundations module) |
| Sessions | One session per Foundations activity |
| Activities | `js/data/foundations/*.js` (5 activities, 112 questions) |
| Questions/blocks | Classification, diagnostic, knowledge-check shapes |
| Renderer | `src/activities/*`, `activity-engine`, programming layers |
| Identity | `hubCode=tlevel-software-development`, `courseKey=t-level-digital-software-development` |

**Schema mapping:** T Level’s flat Foundations catalogue maps to
`week: foundations` → `session: {activityId}` → activity blocks. This preserves
activity order and stable ids without inventing fake multi-week structure.

## Canonical mapping

- Schema: `lp.content` `0.1.0` via `@learning-platform/content`
- Converter: `scripts/import/convert_static_hubs.mjs`
- Question ids: `{activityId}:{originalQuestionId}` with `sourceQuestionId` preserved
- Activity versions: existing semver preserved (`1.0.0`, `2.0.0` for Programming Diagnostic)
- Matching/order types: mapped to implemented block types (`classification`, `short-response`) where the canonical registry has no exact alias
- Difficulty: preserved when present in source; not invented where absent

## Lossy / unsupported constructs

| Item | Handling |
| --- | --- |
| Unit 3 Week 1 Apps Script-only copy | Scaffolding reflection block in package; Git/Apps Script still authoritative for that copy until imported |
| Custom React components (e.g. attacker-types learning UI) | Component stays in repo; title/instructions/questions/feedback from package |
| Hub-specific publication RPCs | Not created — generic `api.published_curriculum_package` only |

## Publication

Initial version: **`0.2.0`** for both hubs (avoids collision with test fixtures at `0.1.x` / `0.3.x`).

Local seeds (publication body only — catalogue already grounded by historical imports):

```bash
python3 scripts/import/generate-curriculum-publication-seed.py --publication-only \
  ../unit-3-Cyber-Security-Hub/content/unit-3-cyber-security \
  supabase/data/generated/seed-unit3-publication.sql

python3 scripts/import/generate-curriculum-publication-seed.py --publication-only \
  ../tlevel-software-development-hub/content/tlevel-software-development \
  supabase/data/generated/seed-tlevel-publication.sql
```

Hosted publication must use **Admin → Publish to Platform**
(`admin_api.publish_curriculum`). Do not hand-insert production rows.

Regenerate packages after static source changes:

```bash
node scripts/import/convert_static_hubs.mjs
```

## Runtime behaviour

Both hubs call `loadUnit3Curriculum` / `loadTLevelCurriculum` from
`useHubPlatform` before adapters become ready.

| Layer | Responsibility |
| --- | --- |
| Core | fetch, validate, cache (`lp.curriculum.cache.v1:{hub}:{course}`), version selection |
| Hub `platform.ts` | `createPlatform({ hubCode, courseKey })`, `validatePackage`, explicit `loadBundled` fallback |
| Hub `apply-runtime.ts` | hydrate window globals / Foundations bootstrap from published package |
| Git data banks | Guarded by `if (globalThis.__lpPublishedCurriculum) return;` — explicit fallback only |

Fallback is logged (`UNIT3_CURRICULUM_FALLBACK` / `TLEVEL_CURRICULUM_FALLBACK`) and
surfaced via `data-curriculum-source` on `<body>`. Remove fallback once hosted
publication is verified stable.

Unit 3 serves the migration fallback package as static JSON at
`content/unit-3-cyber-security/package.json` (not bundled into learner JS).

## Learner evidence

Unchanged. Continue using `api.submit_attempt`, `learning.attempts`,
`learning.responses`, and existing activity version ids. No hub-specific attempt
tables were introduced.

## Admin editing

Admin authoring tests confirm drafts can be opened for Unit 3 and T Level
without Unit 14-only filters (`tests/publication.test.ts`).

Post-migration acceptance (each hub):

1. Open published curriculum in Admin
2. Create draft → edit safe field → validate → publish next semver
3. Reload learner hub (no Git commit / no Pages deploy)
4. Confirm new copy appears and `data-curriculum-source=published`

## Tests

| Suite | Result (local) |
| --- | --- |
| `learning-platform-core` `npm run check` | pass |
| `learning-platform-backend` `supabase test db` (458 tests) | pass |
| `scripts/import/tests/test_static_hub_packages.mjs` | pass |
| Unit 3 hub tests | pass |
| T Level hub tests | pass |
| Unit 14 hub tests | pass |
| Admin `npm run test:authoring` | pass |

## Hosted deployment steps

Completed 2026-08-18:

1. Hosted backend migrations including `fix_curriculum_projection_activity_ids`.
2. Admin Portal deployed (drafts, editing, publication; Unit 3, T Level and Unit 14 visible).
3. Unit 3 and T Level learner runtimes deployed (curriculum from Supabase, not Git).
4. Admin published Unit 3 (`0.2.0` then smoke `0.2.1`) and T Level (first hosted `0.2.1`, smoke `0.2.2`) through `admin_api.publish_curriculum`.
5. Smoke tests: `data-curriculum-source=published`; Admin edit visible after reload; no Git/Pages deploy for teaching copy.

## Smoke test procedure

For each hub with hosted Supabase configured in `SUPABASE_CONFIG`:

1. Sign in as learner; open browser devtools → Network.
2. Confirm RPC `published_curriculum_package` returns package version `0.2.0+`.
3. Confirm `document.body.dataset.curriculumSource === "published"`.
4. Change a visible string in Admin; publish `0.2.1`; hard reload hub; confirm new string.
5. Confirm no hub repository commit was required for step 4.

## Rollback

Preferred: **restore previous published version** in Admin (republish earlier semver or use platform publication history). Learner hub application rollback is a separate, infrequent Git deploy of runtime code only.

If publication is missing, hubs fall back to the explicit Git/static snapshot (observable via fallback banner and console warning).

## Remaining gaps

- Unit 3 Week 1 Apps Script teaching copy is not fully in the package (see Week 1 plan below)
- Git/static fallback remains in hub runtime by design; remove it in a dedicated follow-up after several further production publications
- Hosted T Level first publication is version `0.2.1` (canonical package body); Admin’s shared next-version field had already seen Unit 3 `0.2.0`

### Week 1 Apps Script extraction (plan only)

There is no `apps-script/week-1/` project in the hub. Week 1 still runs through
`activities/activity.html` and the Activity API (`U3-W01-*` / `u3-w01-*`),
including `markSection`. The canonical package includes eight Week 1 activity
ids with scaffolding reflection blocks so the package validates.

Extraction is possible but **not low-risk during cutover**:

1. Export current Activity API banks (prompts, options, feedback) into Admin.
2. Replace scaffolding blocks with real `lp.content` questions.
3. Keep `markSection` on Apps Script until a learner-API equivalent exists.
4. Publish a new package version; do not change Week 1 renderer in the same PR.

Do not rush this into a production cutover. Git remains authoritative for that
Week 1 copy until those steps complete.
