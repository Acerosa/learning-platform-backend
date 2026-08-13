# Backend curriculum publication

Admin remains the authoring system. The backend is the authoritative published
catalogue. Learner hubs consume published catalogue **metadata** only; they are
not updated by this pipeline and never receive Draft or Review states.

```text
Admin Draft → Review → Approved → local Published snapshot
        → admin_api.publish_curriculum
            → platform.curriculum_publications
                → api.published_curriculum (metadata)
```

There is no GitHub automation and no write into learner repositories.

## Pipeline

1. Staff author and review in Admin. Validation in the browser is a gate only.
2. Local Publish freezes an immutable Admin snapshot.
3. **Publish to Platform** sends that snapshot through `admin_api.publish_curriculum`.
4. The backend authenticates `auth.uid()`, requires an active `platform_admin`
   role, validates the package again, then inserts a published row.
5. A newer version for the same hub and course marks the previous published row
   **Superseded**. Historical rows stay.

Accepted lifecycle values: `approved` or `published`.  
Rejected: `draft`, `ready-for-review`, `in-review`, and any other status.

## Backend ownership

| Object | Role |
| --- | --- |
| `platform.curriculum_publications` | Immutable catalogue (package body included) |
| `platform.publish_curriculum` | Authoritative mutation |
| `admin_api.publish_curriculum` | Browser-safe wrapper |
| `admin_api.curriculum_publications` | Staff history (no package body) |
| `api.published_curriculum()` | Learner-safe current metadata |

Existing `learning.activity_versions` catalogue rows are unchanged. This
pipeline registers published `lp.content` packages; exploding them into
delivery activities remains a later learner-hub consumption step.

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

## Audit

Each successful publish writes `curriculum.publication.published` with hub,
course, version, schema version, content package version, author, reviewer,
published-by staff reference and notes. History is not removed.

## Security

- Identity from `auth.uid()` only
- `platform_admin` required
- RLS on the catalogue table; no authenticated INSERT/UPDATE/DELETE
- Duplicate version with a different package is rejected; identical retries are idempotent

## Future learner-hub consumption

`api.published_curriculum()` exposes hub, course, versions and timestamp for
the currently published row. Hubs must not read Admin localStorage. Wiring a
hub renderer to this catalogue is Part 9+ work.
