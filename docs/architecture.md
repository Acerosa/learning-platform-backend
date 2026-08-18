# Architecture

This is the authoritative architecture document for the Learning Platform.
Repository-specific docs describe only that repository's internal boundary.

## Pattern

The implemented pattern is **Contract-First Modular Hub Architecture**:

- **Polyrepo** — one GitHub repository per platform package or learner hub.
- **Modular-monolith backend** — one Supabase project; logical domains in
  `learning` and `platform`; browsers never depend on those schemas.
- **Contract-first integration** — hubs and Admin talk only to versioned
  `api` / `admin_api` contracts and package APIs.
- **Pluggable learner hubs** — leaf applications composed from Core, UI and
  Content; they are not a second backend.
- **Admin control plane** — Central Admin Portal for staff reads, hub
  registry and curriculum publication.
- **Authoritative backend** — identity, enrolment, published curriculum,
  delivery, evidence, results, progress, analytics, RLS and audit.

This is not a microservice architecture. Domains are isolated enough that a
capability could later be extracted if there is a genuine scaling or
organisational reason. Extraction is not a current requirement.

## Content ownership

| Layer | Owns |
| --- | --- |
| GitHub repositories | Application code: hubs, Core, UI, Admin shell, renderers, contracts |
| Supabase | Authoritative **published** curriculum packages, catalogue projections, learner evidence |
| Admin Portal | Curriculum/content **authoring**: drafts, preview, validation, publication requests |

Teaching-content changes (wording, questions, hints, starter code, marking
metadata, resources, differentiated variants) are published through
`admin_api.publish_curriculum`. They do **not** require a Git commit, GitHub
Action, Vite rebuild or GitHub Pages redeploy.

GitHub deployment is still required for application-code changes: new React
components, activity renderers, shared Core, new block types, navigation,
platform contracts and infrastructure.

## Hub curriculum loading

| Hub | Runtime class |
| --- | --- |
| Unit 14 Software Engineering for Business | **DATABASE_DRIVEN** — `platform.curriculum` / `api.published_curriculum_package` |
| Unit 3 Cyber Security | **DATABASE_DRIVEN** — hosted `api.published_curriculum_package`; `data-curriculum-source=published` verified 2026-08-18 |
| T Level Software Development | **DATABASE_DRIVEN** — hosted `api.published_curriculum_package`; `data-curriculum-source=published` verified 2026-08-18 |

Every hub consumes `@learning-platform/core/curriculum-runtime`. Hubs supply
`hubCode` and `courseKey` only. They must not implement publication lookup,
cache keys or schema validation. See Core `docs/curriculum-runtime.md`.

## Difficulty variants

Activities keep a unique stable `id` (the catalogue `stable_key`). Variants
use `metadata.familyId` for the shared family and
`metadata.difficulty` of `foundation` | `standard` | `challenge`. Typical ids
are `{family}-{difficulty}` when that key is free. Optional `metadata.support`
(`scaffolded` | `independent` | `extension`) is reserved and is not a
substitute for difficulty.

## Drafts versus publication

`platform.curriculum_drafts` holds staff working copies with optimistic
`revision` tokens. Learners never read drafts. Live teaching content remains
the current `published` row in `platform.curriculum_publications`. Historic
`learning.attempts` keep the `activity_version_id` used at submission time.

## Polyrepo map

| Repository | Role |
| --- | --- |
| `learning-platform-backend` | Authoritative runtime data and security boundary |
| `learning-platform-admin` | Staff control plane |
| `learning-platform-core` | Shared learner platform behaviour (framework-neutral) |
| `Acerosa-learning-platform-ui` (`@learning-platform/ui`) | Shared React learner presentation |
| `learning-platform-content` | `lp.content.*` schemas, validation, import, generic render |
| `learning-platform-cli` | Golden-path developer tooling (`lp`) |
| `learning-platform-results` | Shared educational interpretation (no persistence) |
| `unit-14-software-engineering-for-business-hub` | Current reference learner hub |
| `unit-3-Cyber-Security-Hub` | Current-generation hub (classic engines retained) |
| `tlevel-software-development-hub` | Current-generation hub (classic engines retained) |

## Dependency direction

```text
CLI
 │
 ▼
Hub ────────► UI
 │            │
 ├──────────► Content
 │
 └──────────► Core
                │
                ▼
              api
                │
                ▼
             Backend
                ▲
                │
            admin_api
                │
              Admin
```

UI may use Core **contracts and tokens** (classes, enumerations, `--lp-*`).
It must not own Auth, API clients or backend authority. Admin may use Core
theme services and Content for authoring preview; it must not use the learner
`createPlatform()` facade as staff authority.

### Dependency rules

- Backend never depends on a hub implementation.
- Core never depends on UI, Content, Admin or a hub.
- Content never depends on a specific hub's teaching copy.
- UI never owns platform state or backend authority.
- Admin never edits hub source code and never queries `learning` / `platform`.
- CLI is development tooling, never runtime infrastructure.
- Hubs are leaf applications.
- Browsers use only approved `api` / `admin_api` contracts.
- Protected schemas remain backend-only.
- GitHub is provenance and deployment, not a runtime data dependency.
  Hub registry rows store reviewed URLs; runtime reads stop at Postgres.

## Modular-monolith domains

Logical domains live in one database. Cross-domain writes go through
SECURITY DEFINER functions and views, not through extra network hops.

| Domain | Principal objects | Extraction now? |
| --- | --- | --- |
| Identity | `auth`, `students`, `teachers` | No |
| Learning organisation | `courses`, `groups`, `enrolments` | No |
| Curriculum | `curriculum_publications`, activities, versions, questions | No |
| Delivery | `activity_delivery`, `activity_assignments` | No |
| Evidence / Results | `attempts`, `responses`, `question_marking` | No — first-class in-process domain |
| Progress | `api.my_activity_progress` and derived views | No |
| Analytics | `admin_api.dashboard_summary`, `activity_performance` | Later warehouse possible |
| Platform | hubs, contracts, roles, audit, health | No |

Acceptable coupling: submission resolves identity → enrolment → assignment →
version in one transaction. That is the product, not a layering bug.

Direct table coupling that should stay behind functions: marking specs,
publication projection, onboarding, hub register/update.

## Evidence / Results / Progress

Do not add parallel tables to match these names. The existing schema already
separates the concepts:

| Concept | Question | Where it lives |
| --- | --- | --- |
| **Evidence** | What did the learner submit? | `learning.responses.response_payload` |
| **Result** | How was that evaluated? | `responses.awarded_score`, `is_correct`, `requires_review`, `marking_source`; attempt `score` / `marking_source` |
| **Progress** | What does that mean for the journey? | Derived views (`api.my_activity_progress`), not a write model |

Teacher review, written/code evidence, first/latest/best, group markbook and
topic/skill analytics extend these columns and additive `admin_api` aggregate
views. See [Admin API](admin-api.md) and [Database model](database.md).

## Future extraction (design for, do not build)

Design for extraction, not premature distribution. The backend remains a
modular monolith. Keep contracts at the API/RPC boundary so these *could*
move later:

- code execution
- notifications / email
- large imports
- search
- analytics warehouse
- AI / RAG
- file / media processing
- monitoring ingestion

Do not introduce queues, brokers, service discovery, distributed transactions
or Kubernetes unless a concrete requirement appears.

## Contract generations

| Contract | Current |
| --- | --- |
| Hub Manifest | `1.0.0` |
| Core | `0.2.x` (supported runtime generation; `0.1.0` remains registered for historical migrations) |
| UI | `0.1.x` |
| Content | `0.1.x` |
| Learner API | `0.1.x` (additive published-package RPC) |
| Submission | `0.1.x` |
| Admin API | `0.2.0` draft |
| Backend foundation tag | `0.1.0` / `curriculum-engine-mvp` |

### Hub classification

| Hub | Class | Notes |
| --- | --- | --- |
| Unit 14 | **Current generation** (reference) | React + TypeScript + Vite MPA, Core 0.2, UI, Content, runtime published package |
| Unit 3 Cyber | **Current generation** | Core 0.2 + UI shell; hosted published package is authoritative; Week 1 Apps Script `markSection` copy still outside the package |
| T Level | **Current generation** | Core 0.2 + UI shell; hosted published package is authoritative; Foundations mapped to a single canonical week |

Do not migrate a hub solely for visual consistency. Classic engines are retained on purpose.

Reviewed `learning-platform-hub.json` files and Hub Registry copies declare Core `0.2.0` for all three hubs.

Compatibility policy: additive contract changes stay on the current major.
Breaking API or schema changes require a new contract version and a tested
overlap period. Hubs declare required versions in `learning-platform-hub.json`.

---

## Backend boundary

This repository implements the backend half of the LHDS / SAD: one learner
identity, one backend, many learner hubs and one Central Admin Portal.

### Ownership

| Platform backend owns | Learner hubs own |
| --- | --- |
| Auth linkage and identity derivation | Subject-specific activities and renderers |
| Learner and staff profiles | Hub presentation, routes and branding |
| Courses, groups and enrolments | Activity engine code and executable behaviour |
| Published curriculum packages and delivery catalogue | Bundled fallback snapshots and static assets |
| Assignments and activity delivery | Browser drafts and harmless UI preferences |
| Attempts, responses, results and progress | Hub manifests supplied for registration |
| Analytics and reporting data | Integration with approved APIs |
| RLS, API/RPC contracts and migrations | Declared platform compatibility |
| Hub registry and platform contracts | No backend infrastructure |
| Administrative data boundary |  |

### Layers and schemas

```text
Presentation
├── learner hubs
└── Central Admin Portal
          │
Application/API
├── api          learner-safe/public views and RPCs
└── admin_api    staff-only boundary (reads plus reviewed mutations)
          │
Domain/data
├── learning     identity, curriculum, delivery, evidence and results
└── platform     registry, contracts, roles, audit, health, publications
          │
Identity
└── auth         Supabase Auth
```

`learning` and `platform` are protected implementation schemas. The public API
surface is not a synonym for direct table access.

### Trust boundary

The browser is untrusted. Learner identity is resolved as:

```text
auth.uid()
  -> learning.students.auth_user_id
  -> active enrolment
  -> assigned activity version
  -> attempt and responses
```

The backend derives enrolment, assignment and attempt numbering. The shared
submission RPC accepts only activity/version keys, a client idempotency key,
structured responses, a relative source page, client timestamps and an
optional programming language.

Staff authority follows a separate path:

```text
auth.uid()
  -> learning.teachers.auth_user_id
  -> platform.staff_roles
  -> admin_api RLS policy
```

A teacher is not automatically a platform administrator.

### Compatibility and extraction

The original backend migration history remains unchanged so a future transfer
can preserve database objects, stable identifiers and learner history. New
changes are appended as forward migrations.

Hub repositories own their root `learning-platform-hub.json`. A reviewed copy
can be validated and converted to migration SQL here, or registered by an
authorised `platform_admin` through `admin_api.register_hub`, or updated
through `admin_api.update_hub`. Runtime registry access terminates at the
database and never reaches GitHub. See `docs/hub-registration.md`.

Version 0.1.0 keeps established learner API signatures. Assignment-aware
multi-course submission is the compatibility correction: a learner with
multiple active enrolments can submit when exactly one enrolled group owns the
activity assignment. Ambiguous assignment is rejected.

### Audit and operations

`platform.audit_events` is append-only. `platform.operational_health` holds
current service health, with a safe projection from `api.platform_health()`
and diagnostics visible only to authorised staff.

No monitoring collector, alerting pipeline or automatic audit trigger is
claimed in this release.

### Known architectural debt

- Existing formative activities may submit client-derived correctness and
  marks. The backend validates ranges and consistency and derives totals, but
  fully server-authoritative marking needs a stronger marking contract.
- Curriculum metadata does not yet implement every LHDS lifecycle and learning
  outcome field.
- Administrative writes other than hub register/update, curriculum
  publication and staff curriculum drafts still require separately designed,
  audited RPCs.
- Teacher markbook, first/latest/best result views and topic/skill analytics
  now have staff read models (`admin_api.attempts` review flag,
  `admin_api.responses`). Interpretation lives in `@learning-platform/results`.
  Teacher editing and moderation remain out of scope.
- T Level's historical `supabase/` tree is extraction provenance, not a second
  backend.
