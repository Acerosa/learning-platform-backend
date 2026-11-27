# Authenticated QA acceptance plan

**Status:** Approved and executed — production synthetic QA provisioning and authenticated acceptance completed.  
**Scope:** Reuse permanent synthetic learner fixtures. No genuine student password resets. No historical assessment rewrites. Credentials never enter git.

Related: [synthetic-qa-learners.md](../../synthetic-qa-learners.md), ops `provision:synthetic-qa` / `check:synthetic-qa`, `npm run accept:authenticated-qa`.

## 1. Approved synthetic personas

| Persona | Student number | Intended group | Hub unlock notes | Smoke activity |
| --- | --- | --- | --- | --- |
| `UNIT3_TEST_LEARNER` | `QA-UNIT3` | `CYBER-TEST-QA` | Unit 3 hub accepts `CYBER-TEST-QA` and `CYBER-TEST-A` | `week2-malware-symptoms` |
| `TLEVEL_TEST_LEARNER` | `QA-TLEVEL` | `TLEVEL-TEST-A` | Exclusive API/isolation fixture. Production T Level hub UI currently unlocks marking only for `TLEVEL-DSD-Y2` | `week-1-lesson-1-ex-01` |
| `TLEVEL_DSD_Y2_TEST_LEARNER` | `QA-TLEVEL-DSD-Y2` | `TLEVEL-DSD-Y2` | Teaching-group browser path for T Level marking/feedback | probe `week-1-lesson-1-ex-07` |
| `UNIT14_TEST_LEARNER` | `QA-UNIT14` | `UNIT14-TEST-A` | Exclusive synthetic group | `week-1-variables-and-data-types` |
| `L2E_TEST_LEARNER` | `QA-L2E` | `L2E-TEST-A` | Exclusive synthetic group | `week-1-knowledge-check` |
| `STAFF_QA_ADMIN` | `STAFF-QA-ADMIN` | n/a | Dedicated staff Auth + `learning.teachers` + `platform_admin` | Admin Portal / Group Generator |

Catalogue: `learning.synthetic_qa_fixtures`. Verify every account against fixture row, `is_synthetic`, Auth metadata (`synthetic=true`, `purpose=formative-smoke-test`, matching `persona`), and intended enrolment — never email alone.

## 2. Environment variables (gitignored `.env`)

Learner pairs (any alias set is accepted):

- `UNIT3_TEST_EMAIL` / `UNIT3_TEST_PASSWORD` (or `SYNTHETIC_QA_EMAIL_UNIT3` / `SYNTHETIC_QA_PASSWORD_UNIT3`)
- `TLEVEL_TEST_EMAIL` / `TLEVEL_TEST_PASSWORD`
- `TLEVEL_DSD_Y2_TEST_EMAIL` / `TLEVEL_DSD_Y2_TEST_PASSWORD`
- `UNIT14_TEST_EMAIL` / `UNIT14_TEST_PASSWORD`
- `L2E_TEST_EMAIL` / `L2E_TEST_PASSWORD`

Staff:

- `STAFF_QA_EMAIL` / `STAFF_QA_PASSWORD` (aliases `ADMIN_QA_*`)

Ops:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` or `SUPABASE_PUBLISHABLE_KEY` — acceptance Auth only
- `SUPABASE_SERVICE_ROLE_KEY` — provision/check only; ignored by `accept:authenticated-qa`

Never commit passwords, tokens, or service-role material. Never print credentials in logs, PRs, or chat.

## 3. Provisioning procedure

```bash
cd learning-platform-backend
npm run provision:synthetic-qa -- --dry-run
npm run check:synthetic-qa
# Apply only when dry-run shows missing Auth/student/enrolment:
npm run provision:synthetic-qa
npm run check:synthetic-qa
```

Reuse Auth users when metadata matches. The provisioner does **not** rotate passwords; use Auth Admin `updateUserById` only for verified synthetic accounts.

### Enrolment drift

Each persona must have exactly one **active** enrolment — the intended group. Withdraw (do not delete) unintended active synthetic enrolments. Preserve:

- historical withdrawn rows
- learner activity history
- intentional `TLEVEL-DSD-Y2` teaching-group fixture for the DSD Y2 persona only

Exclusive QA groups to verify: `CYBER-TEST-QA`, `TLEVEL-TEST-A`, `UNIT14-TEST-A`, `L2E-TEST-A`.

### Staff QA

Do **not** use the learner provisioner. Create/reuse Auth user with synthetic staff metadata, insert `learning.teachers` (`STAFF-QA-ADMIN`), grant `platform.staff_roles.role = platform_admin`.

`platform_admin` is required because Admin Portal MVP grants full admin_api access only for that role (Group Generator session create, People, curriculum, reporting diagnostics).

Lecturer boundary: `SYNTH-TEACHER-A` / `SYNTH-TEACHER-B` remain without `platform_admin` for least-privilege negative checks.

## 4. Automated acceptance

```bash
npm run accept:authenticated-qa
```

Uses publishable/anon key + user sessions only. Strips service-role from the process env if present. Asserts learner Auth, intended-group isolation, and staff `platform_admin` via `admin_api.current_staff_context`.

## 5. Browser acceptance checklist

Learner hubs (use the persona that the hub enrolment gate accepts):

1. Sign-in
2. Enrolment recognition / no unintended join-class gate
3. Published curriculum retrieval
4. Activity navigation
5. Incorrect-answer feedback **visible in DOM** (`.lp-feedback`)
6. Correct-answer feedback **visible in DOM**
7. Explanatory feedback text
8. Short-response / matching / classification where assigned
9. Permitted retries
10. Progress persistence (finish activity; soft navigation where possible) — verify **independently** of auth restore
11. Session restoration after reload (hub Auth storage) — use same-tab `location.reload()` **without** clearing cookies/localStorage/sessionStorage; do **not** treat a new isolated automation context or storage-clearing navigate as a product defect
12. Sign-out

### Session reload methodology (closure finding)

Full-page reload that appeared to “clear” the session under browser automation was an **automation artefact** (context/storage cleared) while soft SPA navigation retained the session. Controlled same-origin reload with storage intact restores Core hub-scoped Auth keys (`sb-<ref>-auth-token--<hubCode>`) and Admin’s unsuffixed key. Cross-hub key isolation is intentional.

Foundations language-aware marking (temporary exclusive assignment or teaching-group assignment required):

- Python / JavaScript / C# correct → marked correct
- Wrong value → incorrect
- Missing / unknown language → fail closed (`is_correct` null, `requires_review`)
- Language-mismatched syntax (e.g. C# semicolon under Python) → incorrect

Admin Portal (staff QA):

- Dashboard, People, Groups, Hubs & Curriculum, Assignments & Results, Analytics, System
- Marking coverage diagnostics (`published_marking_coverage_*`)
- Learner JWT must not read `admin_api.learners` rows

Group Generator:

1. Staff session create  
2. QR / join code  
3. Synthetic learner join  
4. Participant visibility  
5. Team generation  
6. Publish  
7. Learner team visibility  
8. Session restoration  
9. Close  
10. Permission boundaries  

## 6. Reporting isolation

`is_synthetic` is filterable on learner rows and does **not** change RLS. Staff cohort reports should exclude synthetic learners when measuring genuine outcomes (`where not is_synthetic`). Admin directory defaults currently include synthetic rows so QA evidence remains inspectable. Do not introduce blanket RLS hides.

## 7. Cleanup and lifecycle

- Withdraw temporary synthetic enrolments; never delete enrolment history
- Close temporary Group Generator sessions
- Deactivate temporary exclusive-smoke allowlist exceptions after Foundations probes
- Keep QA accounts available; disable with `admin_api.set_synthetic_qa_learner_active(persona, false)` when idle
- Run `npm run check:synthetic-qa` and `npm run accept:authenticated-qa` before significant releases

## 8. Known hub gate notes

Unit 3 accepts `CYBER-TEST-QA`. The T Level hub hard-codes `ACCEPTED_GROUP_CODES = ['TLEVEL-DSD-Y2']`, so browser marking for the exclusive `TLEVEL-TEST-A` persona remains blocked until that hub allowlist is extended (mirroring Unit 3). Use `TLEVEL_DSD_Y2_TEST_LEARNER` for production browser marking until then.

L2E hub hard-codes `ACCEPTED_GROUP_CODES = ['L2E-DELIVERY-A']`, so exclusive `L2E-TEST-A` can authenticate but Check-answer stays behind the join-class gate until the allowlist is extended (maintenance item; API formative checks remain valid).
