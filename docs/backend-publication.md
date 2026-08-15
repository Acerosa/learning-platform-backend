# Backend curriculum publication

Admin remains the authoring system. The backend is the authoritative published
curriculum. Learner hubs fetch the current published canonical package. They
never receive Draft or Review states.

```text
Admin Draft → Review → Approved → local Published snapshot
        → admin_api.publish_curriculum
            → platform.curriculum_publications (canonical package)
            → delivery catalogue projection
                → api.published_curriculum (metadata)
                → api.published_curriculum_package (teaching package)
```

There is no GitHub automation and no write into learner repositories. A
GitHub Pages redeploy is not required for normal curriculum publication.

## Pipeline

1. Staff author and review in Admin. Validation in the browser is a gate only.
2. Local Publish freezes an immutable Admin snapshot.
3. **Publish to Platform** sends that snapshot through `admin_api.publish_curriculum`.
4. The backend authenticates `auth.uid()`, requires an active `platform_admin`
   role, validates the package again, then inserts a published row.
5. The same transaction projects delivery catalogue rows from the canonical
   package. Published activity versions remain immutable.
6. A newer version for the same hub and course marks the previous published row
   **Superseded**. Historical rows stay.

Accepted lifecycle values: `approved` or `published`.  
Rejected: `draft`, `ready-for-review`, `in-review`, and any other status.

## Backend ownership

| Object | Role |
| --- | --- |
| `platform.curriculum_publications` | Canonical immutable package snapshots |
| `platform.publish_curriculum` | Authoritative mutation |
| `platform.project_curriculum_package` | Idempotent catalogue projection |
| `admin_api.publish_curriculum` | Browser-safe wrapper |
| `admin_api.curriculum_publications` | Staff history (no package body) |
| `api.published_curriculum()` | Public current metadata |
| `api.published_curriculum_package(hub, course)` | Public current teaching package |

The canonical package is the source of truth. `learning.activities`,
`learning.activity_versions` and related tables are projections used for
delivery and submissions. OCR assignment briefs stay inside the published
package. `learning.activity_assignments` remains group delivery, not an OCR
assignment catalogue.

## Learner read API

`api.published_curriculum_package(p_hub_code, p_course_key)`:

- returns only the current `published` row
- rejects unknown or unlinked hub/course values
- never returns drafts, in-review snapshots or superseded packages
- omits teacher-note blocks and staff publication fields
- never joins or exposes `learning.question_marking`
- is callable by `anon` and `authenticated` because teaching content is already
  public on GitHub Pages

Learner progress, attempts and marking specs remain authenticated and
RLS-protected.

## Admin responsibilities

- Edit Drafts only.
- Run local validation and review before local Publish.
- Call the RPC only after a local Approved/Published snapshot exists.
- Never send service-role keys. Never query `learning` or `platform` schemas.
- Display Pending / Publishing / Published / Failed for the platform call.

## Validation

Server-side checks, independent of the browser:

- envelope `schema` / `schemaVersion` `0.1.0`
- supported content package version `0.1.0`
- unique ids
- week/session/activity references
- hub and course exist and are linked
- payload hub/course match the snapshot
- version is a new semver greater than any assigned version for that hub/course

## Versioning and rollback

Published rows cannot be updated or deleted, except the controlled status
change `published` → `superseded`. Rollback is **Restore as Draft → Review →
Publish** a new version. Direct revert of published rows is not supported.
Historical activity versions and attempts are not rewritten.

## Audit

Each successful publish writes `curriculum.publication.published`. Catalogue
projection writes `curriculum.catalogue.projected`. History is not removed.

## Security

- Identity from `auth.uid()` only
- `platform_admin` required to publish
- RLS on the catalogue table; no authenticated INSERT/UPDATE/DELETE
- Duplicate version with a different package is rejected; identical retries are idempotent
- Canonical packages cannot be mutated after publication
