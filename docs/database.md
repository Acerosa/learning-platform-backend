# Database model

## Identity and enrolment

- `learning.academic_years`: controlled academic periods.
- `learning.courses`: stable course identities shared across hubs.
- `learning.groups`: course/year cohorts and controlled onboarding options.
- `learning.students`: learner profiles linked one-to-one to Supabase Auth when
  linked.
- `learning.teachers`: staff profiles linked to Supabase Auth.
- `learning.enrolments`: learner-to-group history; one active enrolment per
  learner/group, with multiple concurrent courses supported.
- `learning.teacher_group_access`: scoped teacher access to groups.

## Curriculum and delivery

- `learning.modules`, `topics`, `skills`, `curriculum_weeks`
- `learning.activities`, `activity_versions`, `questions`, `question_marking`
- `learning.question_topics`, `question_skills`
- `learning.coding_languages`, `activity_version_languages`
- `learning.activity_delivery`: curriculum availability metadata.
- `learning.activity_assignments`: group-specific assigned activity versions.

Published activity versions, questions, marking specifications and their
mappings are immutable. Stable keys and semantic versions allow independently
deployed hubs to retain their contracts. `learning.question_marking` is not
granted to authenticated learners.

## Evidence and progress

- `learning.attempts`: one server-numbered learner attempt with idempotency,
  assignment, activity version and timing context.
- `learning.responses`: question-level structured evidence linked to an
  attempt.
- Progress and analytics are derived through API views; there is no separate
  browser-authoritative progress table.

Completed attempts and responses are immutable.

## Platform data

- `platform.hubs`: authoritative hub registration metadata, required contract
  versions, capabilities, canonical manifest and provenance hash.
- `platform.hub_course_links`: explicit hub-to-course relationships.
- `platform.contract_versions`: hub manifest, core, learner, submission and
  admin compatibility versions.
- `platform.staff_roles`: platform-wide staff authorisation distinct from
  teaching-group access.
- `platform.audit_events`: protected, append-only event records.
- `platform.operational_health`: current public status and protected diagnostic
  detail.
- `platform.curriculum_publications`: immutable published `lp.content` snapshots
  with version, schema, author, reviewer and publication notes. See
  [Backend publication](backend-publication.md).

## Seed policy

`supabase/seed.sql` is local-only. It contains six synthetic Auth users,
synthetic learners/staff, test groups, assignments, one isolated demonstration
attempt, two draft hub registrations and local health data. A separate
Synthetic Platform Administrator has a local-only `platform_admin` role so the
Central Admin Portal authentication slice can be demonstrated; Synthetic
Teachers A and B remain ordinary teachers for scoped-access and denial tests.
`.invalid` email addresses prevent accidental delivery.

Production learner/staff exports must never be committed as fixtures.

Repository and deployment URLs have case-insensitive, trailing-slash-normalised
unique indexes. A compatibility trigger rejects hub rows that reference
inactive manifest, core, learner API or submission contracts. Legacy `subject`
and `curriculum_model` fields remain readable for existing registrations but
are optional for standard manifest-driven registration.

## Identifiers and deletion

Core records use UUID primary keys. Cross-repository identities use immutable
stable text keys. Most protected relationships use `ON DELETE RESTRICT` so
learner history cannot be silently removed; response rows cascade only with
their parent attempt.
