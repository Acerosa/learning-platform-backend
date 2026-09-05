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
| Supabase | Authoritative **published** curriculum packages, catalogue projections, learner evidence, **content library** |
| Admin Portal | Curriculum/content **authoring**: drafts, preview, validation, publication requests, **Content Library CRUD and builders** |

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
| Readiness diagnostics | `diagnostic_sessions`, `diagnostic_responses` | No — anonymous, separate from attempts |
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

Readiness diagnostics are a separate anonymous evidence family. They must not
be modelled as `learning.attempts`: there is no `auth.uid()`, no enrolment, no
assignment, and no academic grade. Student name and student ID are reporting
labels only. One trimmed student ID has one sitting per hub, course, and
diagnostic version; `api.start_diagnostic` reuses a `started` sitting and
rejects a `completed` sitting for that version. Writes go through
`api.start_diagnostic`, `api.submit_diagnostic_response`, and
`api.complete_diagnostic`. Submit applies versioned specs from
`learning.diagnostic_question_marking` and never returns marks to the browser.
Staff later read `admin_api.diagnostic_sessions`, `diagnostic_responses`, and
`diagnostic_summary`. See [Learner API](api.md), [Admin API](admin-api.md), and
[Diagnostic versioning](diagnostic-versioning.md).

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

### Content Library (Phase 2)

The `library` schema provides reusable content objects that can be referenced
across curriculum publications without duplication. Tables:

- `library.questions` — reusable questions with rich metadata (type, difficulty,
  marks, learning outcomes, topic, tags, command word, exam board)
- `library.activities` — reusable activities with linked questions
- `library.templates` — activity/assessment templates (multiple-choice, coding, etc.)
- `library.resources` — reusable learning resources (video, PDF, website, repo)
- `library.feedback` — reusable feedback (correct, incorrect, misconception, hint)
- `library.hints` — graduated hints linked to questions
- `library.code_templates` — starter/solution/test code for coding exercises
- `library.assessment_templates` — assessment specifications (marks, duration)
- `library.usage_references` — tracks where library items are used (impact analysis)

All tables have RLS restricted to `platform_admin` / `curriculum_admin` staff.
Admin views (`admin_api.library_*`) expose list and detail reads with `used_by_count`.
RPCs: `save_library_question`, `save_library_activity`, `delete_library_item`,
`publish_library_item`, `archive_library_item`, `duplicate_library_item`,
`get_library_question_detail`, `search_library`.
Reusable items use `draft → published → archived`. Composition searches
published items only. Published rows are not edited in place; a new draft
version is created with `duplicate_library_item`.

Client-side modules:
- `content/library-reuse.ts` — Add From Library, Duplicate From Library, Attach Resource
- `content/builders.ts` — deterministic Retrieval Quiz Builder and Assessment Builder
- `content/library-import-export.ts` — JSON/CSV import, canonical export
- `views/content-library.tsx` — Admin Content Library UI (search, filter, CRUD)

The Content Library does **not** use AI, LLMs or external APIs. All automation
is deterministic and rule-based.

### Composition Engine

The Composition Engine enables curriculum authors to compose curriculum from
reusable library objects instead of manually creating content per week/session.

**Architecture:**

```
Question Library → Activity Library → Composition Engine → Curriculum Draft → Preview → Publish → Learner Hub
```

**Reference model:** Every library item inserted into a curriculum creates a
`library.composition_references` row tracking:
- `instance_id` — the curriculum-local ID of the inserted object
- `library_item_id` — the source library object UUID
- `library_version` — the version at time of insertion
- `state` — `inherited` | `overridden` | `detached`
- `overrides` — JSONB of curriculum-specific property overrides

**Override model:** Curriculum instances can override specific properties
(title, instructions, estimated time, resources) while inheriting everything
else from the library master. State transitions: `inherited` → `overridden` →
`inherited` (via clear). Overrides are stored in the reference row, not in the
content package, keeping the package format unchanged.

**Detach model:** An instance can be detached from its library source, making
it fully independent. Future library changes no longer propagate. Detachment
is one-way — reattaching requires re-inserting from library.

**Update propagation:** `admin_api.composition_update_check` compares
reference versions against current library versions. Authors can: Update
(accept new version, clear overrides), Ignore (keep current version), or
Compare (structural diff viewer). The diff viewer shows added/removed/changed
blocks and metadata changes — pure structural comparison, no AI.

**Coverage analysis:** `analyseCoverage()` computes per-learning-outcome
coverage percentages across all curriculum activities. Shows missing,
underrepresented, and over-covered outcomes.

**Difficulty balance:** `analyseDifficultyBalance()` shows foundation/standard/
challenge distribution across activities.

**Composition templates:** Built-in week templates (`weekly-lesson`,
`practical-lesson`, `revision-lesson`, `assessment-week`, `project-week`)
generate complete week/session/activity scaffolding.

**Curriculum recipes:** Built-in session recipes (`revision-session`,
`retrieval-session`, `practical-session`, `assessment-session`,
`homework-session`) generate session layouts with activity slots.

**Version graph:** `buildVersionGraph()` visualises library item lineage
including difficulty variants.

**Impact analysis:** `admin_api.composition_impact_analysis` shows draft count,
publication count, and total usage for any library item before editing.

**Security:** All composition tables have RLS restricted to
`platform_admin`/`curriculum_admin`. Learner hubs receive only the final
published curriculum package — no composition metadata is exposed.

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

## Phase 4 — Composition Workflow Integration

### Architectural Principle

The Composition Engine is the canonical curriculum authoring experience. It does
**not** publish content directly. It produces standard **Curriculum Drafts** that
flow through the existing Draft → Preview → Validate → Approve → Publish
pipeline. No second publication architecture may be introduced.

### Composition Workflow

```
Content Library
      │
      ▼
Composition Engine
      │
      ▼
Materialisation Layer
      │
      ▼
Curriculum Draft  (AuthoringDraft)
      │
      ▼
Existing Publication Pipeline
      │
      ▼
Published Package → Shared Core Runtime → Learner Hub
```

### Materialisation

The materialisation layer (`src/content/materialise.ts`) transforms a
`CompositionDraft` into a canonical `ContentPackage`:

1. **Reference resolution** — Library references are tracked during composition
   via `CompositionReference` objects. During materialisation, the `_compositionRef`
   metadata marker is stripped so the output is indistinguishable from a manually
   authored package.
2. **Override resolution** — For references in the `overridden` state, each
   override key-value pair is merged into the activity's resolved metadata.
   Learner hubs never receive unresolved overrides.
3. **Detach resolution** — Detached activities are treated as independent; their
   `_compositionRef` marker is removed and no override merge occurs.
4. **Variant resolution** — Variants produce distinct activity instances during
   insertion, resolved identically during materialisation.
5. **Resource inclusion** — Resources attached from the library are already
   embedded as content blocks during composition. Materialisation preserves them.
6. **Canonical output** — `syncCurriculumLists()` ensures all document cross-
   references are consistent. The resulting `ContentPackage` passes the existing
   `publicationGate` validation.

### Draft Integration

- `compositionToDraft()` creates a new `AuthoringDraft` from a composition,
  using the existing `createDraft()` and `touchDraft()` functions.
- `updateDraftFromComposition()` updates an existing draft in-place, maintaining
  the draft's identity (id, revision, metadata) while replacing its package.
- The existing optimistic concurrency model (`remoteRevision`) continues to
  prevent conflicting edits.

### Draft Comparison

`comparePackages()` produces a `PackageDiff` showing added, removed, and changed
activities, weeks, sessions, questions, and metadata fields — enabling the
"Current Draft vs Last Published" comparison view.

### Package Preview

`previewPackageJson()` materialises the composition and serialises the canonical
package as indented JSON, useful for debugging the exact output that will be
published.

### Drag-and-Drop

Visual drag-and-drop uses `@dnd-kit/core` and `@dnd-kit/sortable` for reordering
weeks, sessions, activities, and questions. The `reorderActivities()` and
`reorderQuestions()` functions in the composition engine maintain ordering.

Accessibility hardening adds deterministic Move Up / Move Down fallback controls
for every reorderable level. Composition state changes only on completed
reorders and then flows through the existing draft save path, so failed or
cancelled drag attempts do not persist intermediate order.

### Template and Recipe Management

User-created templates (`library.composition_templates`) and recipes
(`library.curriculum_recipes`) support full CRUD via Admin API RPCs. The
composition UI exposes built-in templates and recipes as well as user-created
ones. Operations: Create, Edit, Duplicate, Archive, Publish.

Built-in templates and recipes remain application-owned defaults. They are
reusable but are not edited in place by curriculum staff. When staff need to
adapt a built-in structure, the intended flow is Duplicate → Custom → Edit.
Archived custom items remain stored for audit/history but are excluded from
normal creation selectors unless the author explicitly includes archived items.

### Duration Metadata and Timeline

Session duration no longer relies on a fabricated per-activity placeholder.
Activities use `metadata.estimatedDurationMinutes` when a duration is known.
Composition resolves duration with deterministic precedence:

1. curriculum-instance override from `CompositionReference.overrides`
2. inherited activity metadata
3. template or recipe slot duration for scaffolded draft activities
4. unknown

Unknown duration stays unknown. The composition UI reports known totals and the
count of activities without estimates rather than inventing a full session
total. Duration editing uses the existing override model for inherited library
content and direct metadata edits for scaffolded non-library activities.

### Inline Library Search

The composition builder includes inline search panels for Activities, Questions,
and Resources. Search queries the `admin_api.search_library` RPC with type
filtering and renders results with an Insert button. No module switching is
required.

### Composition State Reopen

Saving a composition still produces a standard curriculum draft. The draft's
recoverable authoring state is persisted separately through
`admin_api.save_composition_draft_state()` and
`admin_api.get_composition_draft_state()`, backed by
`library.composition_references`. This preserves overrides, detached state,
library lineage, and reorder state across save, reload, and reopen without
introducing a parallel draft model.

### Browser Verification Status

Local browser verification on the composition screen confirmed built-in week and
recipe insertion, keyboard-accessible activity reordering, duration editing,
local Save Composition, page reload, and Reopen Saved restoring the saved draft
identity and reordered structure.

Pointer-drag automation remains partially constrained by browser tooling because
`@dnd-kit` handles do not expose native `draggable` attributes to the MCP drag
command. Keyboard and button-based reordering are therefore the deterministic
verification path today. Live browser verification of custom template/recipe
CRUD and inline library RPC search also depends on a live `admin_api`
connection; in demo mode those controls are intentionally read-only.

### Update Notifications and Conflict Detection

When a referenced library object changes, `findUpdatesAvailable()` detects
version mismatches. The UI displays "Update Available" with options to Compare,
Update, Ignore, or Detach. Conflict detection relies on the existing optimistic
concurrency model.

### Security

Composition permissions mirror curriculum authoring. All composition tables use
RLS restricted to `platform_admin` or `curriculum_admin` roles. No learner
access. No direct protected table writes. Learner hubs receive only published
packages and have no dependency on the Content Library.

### Scope Exclusions

The following remain out of scope: AI/LLM, automatic publishing, automatic
curriculum updates, learner-side composition, and runtime dependency on the
Content Library. Published packages remain immutable.

## Phase 5 — Production readiness

Phase 5 is operational validation of the Platform 1.0 candidate. It does not
add a second architecture.

| Gate | Status 2026-08-18 |
| --- | --- |
| Hosted database (`hubwpkrqndorznwzvaer`, RR NHC Hub) | Applied through Supabase MCP `apply_migration` / `execute_sql` |
| Learner hubs load `data-curriculum-source=published` | Unit 3, T Level, Unit 14 verified |
| Teaching-content publish without Git | Pipeline exists; live packages already served from Postgres |
| Content Library + Composition schema | Hosted; RLS and EXECUTE grants hardened |
| Hosted Admin Phase 4 UI | **Not on GitHub Pages** — local Admin still uncommitted |
| Hosted Library → Compose → Publish loop | **Not proven** — library tables empty; Admin UI missing |

Ordinary teaching-copy changes still must not require Git commits, GitHub
Actions or GitHub Pages. Application-code changes (Admin modules, hub
runtime, Core) still deploy through GitHub.

Hosted schema changes use **Supabase MCP** `apply_migration` / `execute_sql`
on project `hubwpkrqndorznwzvaer`. Local CLI (`supabase db reset`,
`supabase test db`) validates; it does not deploy. See
[Release process](release-process.md) and [Operations](operations.md).
