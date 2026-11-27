# Final authenticated production acceptance report

**Date:** 2026-11-27  
**Backend tip (closure):** `99e1432` (PR #80 merged into `main`)  
**Recommendation:** **Formal recovery closure approved.** Session reload “failure” is an automation artefact, not an application defect. PR #80 is merged with production SQL aligned.

## Provisioning (unchanged from completed exercise)

| Item | Result |
| --- | --- |
| Synthetic identities reused | All five catalogue personas — Auth **REUSE** (metadata PASS) |
| Synthetic identities created | None for learners |
| Staff Auth | Created/reused `STAFF_QA_ADMIN` with synthetic staff metadata |
| Staff roles | `STAFF-QA-ADMIN` teacher + **`platform_admin`** |
| Synthetic enrolment drift | **5 unintended active enrolments withdrawn** (rows preserved) |
| Final isolation | Each fixture persona has exactly one active enrolment (intended group) |
| Remaining limitations | Extra synthetic `QA-L2E-DELIVERY` left unchanged; T Level / L2E hub UI allowlists do not unlock exclusive `TLEVEL-TEST-A` / `L2E-TEST-A` |

Credentials stored only in gitignored `.env`. Not printed in logs/PRs.

## 1. PR #80 merge status

| Check | Result |
| --- | --- |
| CI (Repository Validation, Ops Script Tests, Database Tests, GitGuardian) | **SUCCESS** |
| Merge | **MERGED** at `2026-11-27T14:54:48Z` |
| Merge commit | `99e1432cdbf741d335735d46719413d49cec8302` |
| Hosted migration | `grant_students_synthetic_columns_for_admin_learners` → version **`20261127144141`** |
| Repo migration | `supabase/migrations/20261127160000_grant_students_synthetic_columns_for_admin_learners.sql` |
| Column grants | `authenticated` SELECT on `is_synthetic`, `synthetic_purpose` only; `created_at` SELECT remains **false**; `anon` synthetic SELECT **false** |
| Staff `admin_api.learners` | Rows visible for `platform_admin` |
| Learner JWT `admin_api.learners` | **0 rows** |
| Unintended access | No table-wide SELECT; RLS + view predicate unchanged; learning schema not exposed via public REST beyond existing contracts |
| Production ↔ repo | SQL matches; hosted version clock differs from filename (documented) |

## 2. Page-reload session restoration — root cause

| Classification | **Automation artefact** (not an application defect) |
| --- | --- |
| Architecture | Core `createSupabaseClient`: `persistSession: true`, `autoRefreshToken: true`, hub-scoped `storageKey` via `createAuthStorageKey` → `sb-<ref>-auth-token--<hubCode>`; Admin uses unsuffixed `sb-<ref>-auth-token` |
| Misleading signal | Cursor/Playwright `browser_navigate` / new isolated context / CDP storage clears can drop auth keys while soft SPA navigation retains them |
| Controlled evidence | Same-tab `location.reload()` **without** clearing cookies/localStorage/sessionStorage restores session on T Level, Unit 3, Admin |
| Cross-hub | Hub storage keys intentionally isolate sessions; navigating Unit 3 → Unit 14 requires that hub’s own sign-in (expected) |
| App defect? | **No** — no Core/hub persistence fix required; do not extend session lifetimes |

## 3. Authentication persistence by application

| Application | Sign-in | Soft SPA | Full reload (storage intact) | Same-origin tab | Explicit sign-out |
| --- | --- | --- | --- | --- | --- |
| T Level hub | PASS | PASS | PASS | PASS (async restore) | PASS (prior) |
| Unit 3 hub | PASS | PASS | PASS | — | PASS |
| Unit 14 hub | PASS | PASS | — | — | — |
| L2E hub | PASS (signed in) | — | — | — | PASS |
| Central Admin Portal | PASS | PASS | PASS | PASS | — |
| Group Generator | PASS (prior E2E) | — | — | — | — |

Closing/reopening the browser for persistent sessions is supported by `persistSession: true` + localStorage; not re-exercised as a multi-hour browser restart in this closure pass. Token refresh remains Core `autoRefreshToken: true`. Invalid/expired sessions continue to fail closed via existing Auth + hub recovery paths (Core unit coverage).

## 4. Progress restoration (independent of auth)

| Hub / activity | Auth after reload | Progress / feedback after reload |
| --- | --- | --- |
| T Level week-1 ex-01 | PASS | PASS (prior controlled reload) |
| Unit 3 `week2-malware-symptoms` | PASS | PASS — `.lp-feedback` Correct + selected option restored after `location.reload()` |

Auth restore alone was **not** treated as proof of progress restore.

## 5. Browser feedback verification

| Hub | Incorrect `.lp-feedback` | Correct `.lp-feedback` | Notes |
| --- | --- | --- | --- |
| T Level (DSD Y2) | PASS (prior) | PASS (prior) | Teaching-group path |
| Unit 3 | PASS | PASS | Malware symptoms |
| Unit 14 | PASS | PASS | Week 1 baseline |
| L2E | Sign-in PASS; Check blocked by hub allowlist | — | Hub `ACCEPTED_GROUP_CODES = ['L2E-DELIVERY-A']` rejects exclusive `L2E-TEST-A` (same class as T Level exclusive allowlist). API formative wrong/right remains **PASS** |

## 6. Additional fixes / PRs

| Item | Status |
| --- | --- |
| Application auth/progress code changes | **None required** |
| PR #80 (migration + harness + docs) | Merged |
| This closure docs / checklist / migration mapping | Follow-up PR on `docs/final-recovery-closure` |

## 7. Regression / CI

| Suite | Result |
| --- | --- |
| PR #80 CI | All required checks SUCCESS |
| Ops `authenticated-qa-acceptance` unit tests | 5/5 (prior); checklist regression extended in closure PR |
| Core auth persistence / hub-session recovery | Existing unit tests retain coverage; no defect fix |
| Production marking gaps | **0** (`admin_api.published_marking_coverage_gaps`) |
| Sanitisation | Published curriculum remains **`lp.strip.v2`** |

## 8. Production deployment verification

- Migration `grant_students_synthetic_columns_for_admin_learners` present on hosted project as `20261127144141`.
- Admin People / Group Generator remain reachable for Staff QA after reload.
- Learner JWT still cannot enumerate admin learners.
- No genuine learner records modified in this closure pass.

## 9. Security and data integrity

| Check | Result |
| --- | --- |
| Genuine learners / enrolments | Unchanged vs prior baseline (no genuine writes) |
| Synthetic fixtures | Five intended active enrolments; withdrawn drift preserved |
| RLS / enrolment isolation / marking security | Not weakened |
| Column grants least privilege | Confirmed (synthetic columns only) |
| Credentials in source control | No |

## 10. Remaining independent maintenance (not recovery blockers)

1. **T Level exclusive QA group allowlist** — extend hub `ACCEPTED_GROUP_CODES` to include `TLEVEL-TEST-A` (mirror Unit 3) for exclusive-persona browser marking.
2. **L2E exclusive QA group allowlist** — same pattern: hub currently unlocks only `L2E-DELIVERY-A`, so `L2E-TEST-A` can sign in but cannot Check-answer in UI.
3. **Cohort-report synthetic learner filter** — default-hide synthetic in genuine cohort stats with explicit “include QA” toggle. If synthetics are confirmed to distort genuine cohort statistics, treat as a **reporting defect**, not cosmetic UX.
4. Broader reporting UX improvements (optional).
5. Historical marking remediation and broad migration-history reconciliation remain **out of scope**.

## Closure recommendation

Session restoration is resolved as a **non-application** automation artefact with controlled reload evidence. PR #80 has passed CI and merged with production alignment. Essential authenticated production workflows remain verified.

**Recommend formal recovery closure.** Do not reopen completed recovery work without evidence of a regression.
