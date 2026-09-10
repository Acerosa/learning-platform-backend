# Authoritative current activity assignment membership (Phase 1A.1)

## Problem

`learning.activity_assignments` is unique on `(group_id, activity_version_id)`.
Curriculum projection and delivery activation can leave **multiple versions** of
the same logical activity (`activities.stable_key`) active for one group.

Phase 1A `api.my_hub_activity_progress` originally returned one row per active
assignment version, so older versions inflated required / incomplete counts.

## Why assignments are not deactivated

Version-pinned learner APIs resolve by exact `activity_key` + `activity_version`:

- `api.submit_attempt`
- `api.mark_formative_response`
- `api.save_activity_state` / `get_activity_state` / `clear_activity_state`

Fixtures and live catalogues legitimately keep older versions assigned while a
newer version is also active (for example Cyber `week2-malware-symptoms` 1.0.0
alongside 1.1.0, and dual-version activity-state tests). Deactivating older
assignments breaks those APIs.

Therefore Phase 1A.1 **does not** mutate `activity_assignments.active`.
Assignment-level “one active version per key” uniqueness remains a separate
design decision.

## Authoritative reporting rule

For one **group** and one **activity** among **active** assignments:

1. Prefer `activity_versions.retired_at is null`
2. Then latest `activity_versions.published_at`
3. Then `activity_versions.version` text (tie-break only)
4. Then highest `activity_assignments.id`

Helper: `learning.current_activity_assignment_id(group_id, activity_id)`.

`api.my_hub_activity_progress` returns only that assignment. Contract unchanged:
same columns, one row per logical current membership.

## Historical data

- Assignment rows are left intact (including multiple active versions).
- Attempts and responses stay on the version/assignment used at submit time.
- Completing an old version does **not** complete a newer current version.

## Cross-hub audit (hosted, read-only, pre-fix)

| Hub | Active rows | Distinct keys | Multi-version keys | Reporting inflation |
| --- | ---: | ---: | ---: | --- |
| unit-3-cyber-security | 223 | 127 | 76 | yes |
| tlevel-software-development | 296 | 296 | 0 | no |
| l2e-exploring-emerging-digital-technologies | 45 | 44 | 1 | mild |
| unit-14-software-engineering-for-business | 24 | 24 | 0 | no |

## Unit 3 Session 1 / `u3-w01-definition-gap`

Authoritative required membership for reporting is hub-bound **current**
assignments (via the rule above), not hub package JSON alone.

`u3-w01-definition-gap` appears in the published Unit 3 package session list
but has no hosted `learning.activities` / delivery / assignment row. It is
**not** current required work and is not auto-assigned by this fix.

Week 1 (CYBER-TEST-A, hosted read-only, current selection):

- Session 1 required count: **27**
- Session 2 required count: **28**

## Hosted apply

Migration `20260910140000_reporting_current_assignment_membership.sql` is
local-only until separate review. Do **not** run `supabase db push` or MCP
`apply_migration` as part of Phase 1A.1 merge prep. No assignment-row cleanup
migration is included (by design).
