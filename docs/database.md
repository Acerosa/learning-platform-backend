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

Canonical published teaching packages live in
`platform.curriculum_publications`. Staff working copies live in
`platform.curriculum_drafts` and are never learner-visible. Catalogue tables
are projections used for delivery and submissions, not a second authoring
source.

## Content library and composition

Reusable authoring objects live in the `library` schema. Learners never read
these tables. Staff use `admin_api` views and SECURITY DEFINER RPCs.

| Table | Role |
| --- | --- |
| `library.questions`, `activities`, `templates`, `resources`, `feedback`, `hints`, `code_templates`, `assessment_templates` | Reusable library objects |
| `library.activity_questions`, `activity_resources`, `activity_learning_outcomes`, `question_*` | Library joins |
| `library.usage_references` | Usage / impact tracking |
| `library.composition_references` | Draft reopen state (overrides, detach, lineage) |
| `library.composition_templates`, `curriculum_recipes` | Custom templates and recipes |

Materialisation in Admin produces a standard curriculum draft. Publication
still goes through `admin_api.publish_curriculum`.

## Evidence, results and progress

These are one domain with three meanings. They are not three table families.

**Evidence** is what the learner submitted:

- `learning.responses.response_payload` (selected answers, written text, code,
  reflections, classifications, structured artefacts)
- attempt context: `client_attempt_id`, `source_page`, timestamps,
  optional programming language

**Result** is how that evidence was evaluated:

- `learning.responses.awarded_score`, `max_score`, `is_correct`,
  `requires_review`, `marking_source`, `marked_at`, `feedback_summary`,
  `feedback_next_step`
- `learning.attempts.score`, `max_score`, `status`, `marking_source`,
  `evidence_level`
- protected `learning.question_marking` for server-side formative specs
  (never learner-readable)

`requires_review = true` with `is_correct` null is the existing hook for
teacher-reviewed written/code/reflection evidence. Staff complete reviews
through `admin_api.review_response`, which updates mark/feedback fields only
and never changes `response_payload`.

**Progress** is what the result means for the journey:

- derived views such as `api.my_activity_progress` (completion, attempt
  counts, first/latest/best where the view defines them)
- `admin_api.dashboard_summary` and `activity_performance` for staff
- `admin_api.responses` for staff question-level evidence and marks
- attempt summaries now include `requires_review` and `question_count`
- no browser-authoritative progress table

Completed attempts and responses remain immutable for ordinary clients.
The security-definer review path may update mark and feedback columns only.
Historical attempts stay attached to the activity version that was current at
submission. Group markbook, question diagnostics and topic/skill aggregates use
existing `question_topics` / `question_skills` mappings rather than duplicate
attempt rows.

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
