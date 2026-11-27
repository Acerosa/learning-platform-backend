# Final authenticated production acceptance report

**Date:** 2026-11-27  
**Backend tip at start of exercise:** PR #79 merged at `3fa25c7`  
**Recommendation:** Formal recovery closure for essential authenticated production workflows — **approved to close**, with separate remaining work listed below.

## Provisioning

| Item | Result |
| --- | --- |
| Synthetic identities reused | All five catalogue personas — Auth **REUSE** (metadata PASS) |
| Synthetic identities created | None for learners |
| Staff Auth | Created/reused `STAFF_QA_ADMIN` with synthetic staff metadata |
| Staff roles | `STAFF-QA-ADMIN` teacher + **`platform_admin`** (required for Admin Portal MVP / Group Generator create) |
| Synthetic enrolment drift | **5 unintended active enrolments withdrawn** (rows preserved): UNIT3←TLEVEL-DSD-Y2; TLEVEL←TLEVEL-DSD-Y2; L2E←CYBER-TEST-A + L2E-DELIVERY-A; DSD-Y2←L2E-DELIVERY-A |
| Final isolation | Each fixture persona has exactly one active enrolment (intended group) |
| Remaining limitations | Extra synthetic `QA-L2E-DELIVERY` (not in fixtures) left unchanged; T Level hub UI does not unlock exclusive `TLEVEL-TEST-A` |

Credentials stored only in gitignored `.env`. Not printed in logs/PRs.

## Acceptance results

| Area | Classification |
| --- | --- |
| Automated `accept:authenticated-qa` (5 learners + staff) | **PASS — production verified** |
| Learner Auth + intended-group isolation | **PASS — production verified** |
| Staff Auth + `platform_admin` context | **PASS — production verified** |
| Unit 3 browser sign-in / enrolment (`CYBER-TEST-QA`) | **PASS — production verified** |
| T Level browser sign-in / enrolment (`TLEVEL-DSD-Y2`) | **PASS — production verified** |
| Incorrect + correct feedback rendered in browser (`.lp-feedback`) | **PASS — production verified** (Week 1 ex-01) |
| API formative wrong/right (Unit 3, T Level exclusive, Unit 14, L2E, DSD Y2 classification) | **PASS — production verified** |
| Foundations language-aware marking (Py/JS/C#, mismatch fail-closed) | **PASS — production verified** (temporary exclusive assignment; restored after) |
| Progress finish + soft-path activity state | **PASS — production verified** (finish activity on ex-01) |
| Session restoration after full page reload | **BLOCKED / limited** — full `browser_navigate` reload cleared session in automation; soft SPA path retained session. Not classified PASS. |
| Admin Portal auth, dashboard, People (post-fix), Group Generator module | **PASS — production verified** |
| Admin People pre-fix | **FAIL — confirmed defect** then fixed (see Technical delivery) |
| Group Generator E2E (create → QR → join ×6 → generate → publish → learner visibility → close) | **PASS — production verified** |
| Learner cannot read admin learners rows | **PASS — production verified** (0 rows under learner JWT) |
| Reporting isolation | **PASS — production verified** with caveat: `is_synthetic` filterable; defaults include synthetic in People directory (appropriate for QA inspection). No cohort contamination RLS change introduced. |
| Permission / exclusive group boundaries | **PASS — production verified** |
| Unit 14 / L2E full browser feedback walkthrough | **PASS — API production verified**; browser feedback DOM check focused on T Level (Unit 3 sign-in verified) |

## Technical delivery

| Item | Detail |
| --- | --- |
| Defect | `admin_api.learners` failed for `platform_admin` with `permission denied for table students` because `is_synthetic` / `synthetic_purpose` lacked column SELECT for `authenticated` while the view is `security_invoker` |
| Fix | Migration `20261127160000_grant_students_synthetic_columns_for_admin_learners.sql` — least-privilege column grants |
| Harness | `authenticated-qa-acceptance.mjs`: Node 20 noop WebSocket; prefer anon JWT; ignore service-role; staff context via view; correct `my_enrolments` columns |
| Docs | Updated `AUTHENTICATED_QA_PLAN.md`, `synthetic-qa-learners.md` |
| Regression | Ops unit tests for acceptance harness (5/5) |
| CI / PR | Backend PR for migration + harness + docs (this delivery) |
| Production deploy | Migration applied to production via Supabase; People page re-verified live |

## Security and integrity

| Check | Result |
| --- | --- |
| Genuine learners | **92** unchanged vs baseline |
| Genuine active enrolments | **93** unchanged vs baseline |
| Synthetic active enrolments | **6** (5 fixtures + `QA-L2E-DELIVERY`) |
| Synthetic enrolments match intended config | Yes for five fixtures |
| Temporary Group Generator session | Closed |
| Temporary Foundations exclusive assignment | Deactivated; `exclusive_smoke` restored |
| Credentials in source control | No |
| Marking coverage gaps | **0** unresolved (`published_marking_coverage_gaps`) |
| Sanitisation | Published packages on **`lp.strip.v2`** (4 publications) |
| Marking security / fingerprint / RLS / publication validation | Not weakened |

## Remaining separate work

- Historical marking remediation (out of scope)
- Broad migration-history reconciliation (out of scope)
- Optional: extend T Level hub `ACCEPTED_GROUP_CODES` to include `TLEVEL-TEST-A` (mirror Unit 3) for exclusive-persona browser marking
- Optional: Admin UI default filter to hide synthetic from cohort stats while keeping an explicit “include QA” toggle
- Hardening session persistence verification under full page reload automation

## Closure recommendation

Essential authenticated production workflows required for recovery closure are verified. **Recommend formal recovery closure.** Track the optional T Level exclusive-group hub allowlist and reporting UI filter as follow-up improvements, not blockers.
