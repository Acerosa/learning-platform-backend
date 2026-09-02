# Synthetic QA learners

Permanent hub-isolated synthetic learners used to verify the shared-Auth,
enrolment-scoped learning model. They are ordinary learner accounts with
`is_synthetic` metadata. They do not receive special RLS rules.

## Isolation model

One shared Supabase Auth project. Authentication alone does not grant hub
access. Each QA learner is enrolled in exactly one synthetic group:

| Persona | Group | Hub / module |
| --- | --- | --- |
| `UNIT3_TEST_LEARNER` | `CYBER-TEST-QA` | Unit 3 Cyber Security |
| `TLEVEL_TEST_LEARNER` | `TLEVEL-TEST-A` | T Level Software Development |
| `UNIT14_TEST_LEARNER` | `UNIT14-TEST-A` | Unit 14 Software Engineering for Business |
| `L2E_TEST_LEARNER` | `L2E-TEST-A` | Exploring Emerging Digital Technologies |

`CYBER-TEST-A` is legacy mixed infrastructure and is not the Unit 3 QA fixture.
`TLEVEL-DSD-Y2` is a real teaching group and must not be reused.

Published teaching packages remain publicly readable. That is
`PUBLIC_CONTENT_VISIBLE`, not authorised assignment or evidence access.

## Provisioning

Auth users are created only through the Supabase Auth Admin API. Application
rows are created by `admin_api.provision_synthetic_qa_learner(auth_user_id, persona)`.
Email is not stored on `learning.students` for these fixtures.

```bash
cp .env.example .env
# Fill controlled mailbox aliases and generated passwords. Do not commit .env.
node scripts/ops/provision-synthetic-qa-learners.mjs --dry-run
node scripts/ops/provision-synthetic-qa-learners.mjs
```

If the service role cannot be used safely, create the four Auth users in the
Supabase Dashboard (email/password, confirm email, user metadata
`synthetic=true`, `purpose=formative-smoke-test`, `persona=<PERSONA>`), then
call the provision RPC with each Auth user UUID. Never paste passwords into
SQL, migrations, chat logs or git.

## Lifecycle

Disable temporarily:

```sql
select * from admin_api.set_synthetic_qa_learner_active('UNIT3_TEST_LEARNER', false);
```

Re-enable with `true`. This sets `learning.students.active` and does not delete
Auth, enrolments, formative checks or attempts.

Reset progress: formative checks and completed attempts are immutable. Keep
them as QA evidence. For a fresh browser smoke, use new client check IDs.
Do not delete evidence by default.

Reseed assignments:

```sql
select * from admin_api.ensure_synthetic_qa_groups();
```

This upserts only the catalogued smoke activity (latest published,
non-retired version) for each fixture. Exclusive-smoke groups
(`CYBER-TEST-QA`, `TLEVEL-TEST-A`, `L2E-TEST-A`) keep only that assignment
active; later curriculum publication cannot silently enlarge them.
Reused `UNIT14-TEST-A` keeps historical catalogue assignments already present.

Rotate credentials: generate a new password outside the repo and set it with
the Auth Admin API or Dashboard. Do not write the password to git.

Archive old test evidence: leave rows in place. Filter staff views with
`is_synthetic`. Deletion is exceptional and is not automated.

## Smoke activities

| Hub | Activity key |
| --- | --- |
| Unit 3 | `week2-malware-symptoms` |
| T Level | `week-1-lesson-1-retrieval` |
| Unit 14 | `week-1-variables-and-data-types` |
| L2E | `week-1-knowledge-check` |
