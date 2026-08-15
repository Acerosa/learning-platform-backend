# Content ownership audit

Classification of significant content sources before database-first delivery.
Unit 14 is the reference implementation. Unit 3 and T Level are audited only.

Legend:

- **A** — should live in the database
- **B** — should remain in Git / the application
- **C** — transitional / needs a future model

Do not migrate executable code, React components, CSS, or subject-specific
engines into Postgres.

## Unit 14 — migrated now

| Source | Class | Reasoning |
| --- | --- | --- |
| `content/unit-14/` canonical package (weeks, sessions, activities, blocks, LOs, assignment briefs) | **A** | Authoritative, structured, publication-controlled teaching content |
| Curriculum package version and publication snapshots | **A** | `platform.curriculum_publications` |
| Activity catalogue / versions / questions / delivery | **A** | Projection from the canonical package |
| Learner progress, attempts, responses | **A** | Already backend-owned |
| Hub/course registration metadata | **A** | Already backend-owned |
| OCR assignment briefs inside the package | **A** (in package) | Not exploded into `learning.activity_assignments` |
| React/Vite shell, CSS, activity engine adapters | **B** | Application runtime |
| Bundled `content/unit-14/` snapshot | **B** | Fallback/provenance only |
| Binary assets | **B** | None yet; keep files/CDN if introduced |
| `learning.question_marking` | **A** (protected) | Server-side only; never learner-readable |

## Unit 3 Cyber Security — do not migrate now

| Source | Class | Reasoning |
| --- | --- | --- |
| Week titles, session lists, teaching copy | **A** later | Can map to `lp.content.week` / `session` after canonicalisation |
| Activity catalogues and registries | **A** later | Planner/catalog metadata |
| Week 2–7 question/scenario banks | **A** later | Teaching content currently in hub JS |
| Week 1 Activity API / Apps Script banks | **C** | Already remote; replace with protected backend marking later |
| TryHackMe room copy and URLs | **A** copy / **C** model | External practicals need a schema beyond current blocks |
| Per-activity `app.js`, OCR IIFE engines, peer marking | **B** | Hub runtime |
| Week 1 `markSection` path | **B** | Must stay hub/Apps Script until a marking contract exists |
| NCSC/TryHackMe integrations | **B** | Runtime integrations |
| Apps Script rollback and `/exec` routing | **B** | Operations, not curriculum |
| Northbank narrative duplication | **C** | Shared scenario/asset model later |

Future path: author an `lp.content` package, lift banks into blocks where types
exist, keep Week 1 protected marking until backend marking replaces Activity
API, and model external practicals as a later extension. Do not force this
content into the current package.

## T Level Software Development — do not migrate now

| Source | Class | Reasoning |
| --- | --- | --- |
| Foundations catalog and question banks | **A** later | Curriculum items, not week-shaped |
| Skills/topics in the Foundations manifest | **A** later | Taxonomy |
| Language-variant questions | **C** | Needs a language-variant content model |
| Task/project/assessment placeholders | **A** when authored | Occupational structure ≠ teaching-week schema |
| Language picker, code checker, editors | **B** | Runtime |
| Foundations activity engine and marking | **B** | Hub-owned execution model |
| Project-specific UI | **B** | Presentation |
| `foundations-manifest.json` seed | **C** | Bridge until a T Level package exists |

Future path: map Foundations to a module + activities without inventing fake
weeks. Keep language selection and checking in the hub. Replace the numeric
manifest with validated `lp.content.*` only when Admin can publish T Level.

## Resources / assets

Move resource metadata (title, description, URL, type, week/session) to the
database when it is useful. Do not store binary assets in Postgres. Supabase
Storage can be considered later; it is not required for Unit 14.
