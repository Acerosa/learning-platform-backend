# Authenticated QA acceptance plan

**Status:** Ready for approval — **do not create or modify production Auth identities until this plan is explicitly approved.**  
**Scope:** Reuse permanent synthetic learner fixtures. No genuine student password resets. No historical assessment rewrites. Credentials never enter git.

Related: [synthetic-qa-learners.md](../../synthetic-qa-learners.md), ops `provision:synthetic-qa` / `check:synthetic-qa`, `npm run accept:authenticated-qa`.

## 1. Existing infrastructure (production inventory)

### Synthetic learner application rows

All five catalogue personas exist as `learning.students` with `is_synthetic=true`, `synthetic_purpose=formative-smoke-test`, and linked `auth_user_id`:

| Persona | Student number | Intended group | Smoke activity |
| --- | --- | --- | --- |
| `UNIT3_TEST_LEARNER` | `QA-UNIT3` | `CYBER-TEST-QA` (synthetic, closed) | `week2-malware-symptoms` |
| `TLEVEL_TEST_LEARNER` | `QA-TLEVEL` | `TLEVEL-TEST-A` (synthetic, closed) | `week-1-lesson-1-ex-01` |
| `TLEVEL_DSD_Y2_TEST_LEARNER` | `QA-TLEVEL-DSD-Y2` | `TLEVEL-DSD-Y2` (real teaching group) | probe `week-1-lesson-1-ex-07` |
| `UNIT14_TEST_LEARNER` | `QA-UNIT14` | `UNIT14-TEST-A` (synthetic, closed) | `week-1-variables-and-data-types` |
| `L2E_TEST_LEARNER` | `QA-L2E` | `L2E-TEST-A` (synthetic, closed) | Week 1 Check set / `week-1-knowledge-check` |

Catalogue: `learning.synthetic_qa_fixtures`.  
Admin RPCs: `inspect_synthetic_qa_learners`, `inspect_synthetic_qa_auth_user`, `provision_synthetic_qa_learner`, `ensure_synthetic_qa_groups`, `set_synthetic_qa_learner_active`.

### Auth identities

Application rows report `auth_user_id` present for every synthetic learner. Password material is **not** available in repository env files. Auth reuse requires approved email/password pairs that match existing Auth users with metadata `synthetic=true`, `purpose=formative-smoke-test`, `persona=<PERSONA>`.

### Enrolment drift (pre-approval finding)

Docs require **one exclusive group per persona**. Production currently shows extra **active** enrolments on some fixtures (including non-QA groups such as `TLEVEL-DSD-Y2` / `L2E-DELIVERY-A` / `CYBER-TEST-A`). This weakens hub isolation checks. Remediation is a separate approved ops step (withdraw unintended synthetic enrolments only). Do not touch genuine learners.

### Staff / administrator QA

There is **no** synthetic staff provisioner. Admin Portal full access requires an active teacher with `platform_admin` (portal grants `*` only for that role). Group Generator session creation uses authenticated `admin_api` RPCs; learner join is anonymous (`api.join_grouping_session`). Lecturer-style checks need a teacher with least-privilege roles appropriate to the Admin module under test.

### Reporting exclusion

`is_synthetic` / `synthetic_purpose` are first-class flags for ops filtering. They do **not** change RLS. Staff reporting should filter `is_synthetic` when measuring genuine cohort outcomes; deletion of QA evidence is exceptional and not automated.

### Safe reset (synthetic only)

| Action | Command / API | Effect |
| --- | --- | --- |
| Disable learner | `admin_api.set_synthetic_qa_learner_active(persona, false)` | Soft-disable student row |
| Reseed assignments | `admin_api.ensure_synthetic_qa_groups()` | Upsert allowlisted smoke assignments for exclusive synthetic groups |
| Fresh formative checks | New client check IDs | Append-only; do not delete evidence |
| Rotate password | Auth Admin / Dashboard outside git | Never commit the value |

## 2. Minimum accounts (after approval)

| Account | Role | Purpose | Env (email / password) |
| --- | --- | --- | --- |
| Unit 3 learner | synthetic learner | Marking, feedback, progress, isolation | `UNIT3_TEST_EMAIL` / `UNIT3_TEST_PASSWORD` |
| T Level exclusive learner | synthetic learner | Foundations language marking, progress | `TLEVEL_TEST_EMAIL` / `TLEVEL_TEST_PASSWORD` |
| T Level DSD Y2 learner | synthetic learner | Teaching-group enrolment path | `TLEVEL_DSD_Y2_TEST_EMAIL` / `TLEVEL_DSD_Y2_TEST_PASSWORD` |
| Unit 14 learner | synthetic learner | Cross-hub isolation | `UNIT14_TEST_EMAIL` / `UNIT14_TEST_PASSWORD` |
| L2E learner | synthetic learner | Cross-hub isolation | `L2E_TEST_EMAIL` / `L2E_TEST_PASSWORD` |
| Staff QA (Admin) | `platform_admin` (least extra roles) | Admin Portal, Group Generator create, reporting | `STAFF_QA_EMAIL` / `STAFF_QA_PASSWORD` |

Alternate env names already accepted for learners: `SYNTHETIC_QA_EMAIL_*` / `SYNTHETIC_QA_PASSWORD_*` (see `.env.example`).

Ops-only (never `VITE_` / `NEXT_PUBLIC_`):

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` — provision/check only; unset after use
- Publishable URL/key for browser hubs/Admin (existing hub/Admin public config)

## 3. Secure provisioning instructions (approval gate)

1. Review this plan and the enrolment-drift finding.
2. Place secrets only in gitignored `learning-platform-backend/.env` (or a sealed ops secret store).
3. Prefer **reuse** of existing Auth users: confirm Dashboard metadata, then:

```bash
cd learning-platform-backend
npm run provision:synthetic-qa -- --dry-run
npm run check:synthetic-qa
# Only after approval, if Auth users are missing:
npm run provision:synthetic-qa
```

4. Staff QA: create or designate one Auth user + teacher + `platform_admin` through existing Admin bootstrap/ops process — **not** the learner provisioner (learner tool refuses staff metadata).
5. Optional approved cleanup: withdraw synthetic active enrolments outside each persona’s intended `group_code`.
6. Unset `SUPABASE_SERVICE_ROLE_KEY` when finished.
7. Run acceptance:

```bash
npm run accept:authenticated-qa
# Browser checklist in the same doc / harness --browser-checklist
```

Never paste passwords into SQL, chat, commits, or CI logs.

## 4. Automated acceptance harness

`scripts/ops/authenticated-qa-acceptance.mjs`:

- Loads gitignored `.env`
- Masks emails/ids in output
- Exits **skipped** when learner/staff secrets are absent (blocker documented)
- When secrets present: Auth sign-in, enrolment/group assertions, smoke activity assignment readiness, optional staff session probe
- Does not modify genuine learner rows; does not print secrets

Unit tests cover skip/masking/plan logic without live credentials.

## 5. Local / staging results (credentials absent)

| Check | Result |
| --- | --- |
| Provisioner unit tests | PASS (9/9) |
| `accept:authenticated-qa` without secrets | SKIP — missing approved QA env |
| Local language-aware marking / formative contract / publish gate | Previously PASS (recovery acceptance) |
| Production browser authenticated flows | BLOCKED — no approved passwords in env |

## 6. Production acceptance (after approval)

Execute `npm run accept:authenticated-qa` then browser smoke on each hub + Admin + Group Generator using synthetic accounts only. Record PASS/FAIL per workflow without emails, names of real students, or secrets.
