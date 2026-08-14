# Backend architecture

## Governing standards

This repository implements the backend boundary defined by the Learning Hub
Development Standard (LHDS) and Learning Platform Software Architecture
Document (SAD): one learner identity, one backend, many learner hubs and one
Central Admin Portal.

The standards are authoritative. This document records how version 0.1.0
realises them and where implementation is intentionally incomplete.

## Ownership

| Platform backend owns | Learner hubs own |
| --- | --- |
| Auth linkage and identity derivation | Curriculum content |
| Learner and staff profiles | Subject-specific activities and renderers |
| Courses, groups and enrolments | Hub presentation, routes and branding |
| Assignments and activity delivery | Learning resources and subject guidance |
| Attempts, responses and progress | Browser drafts and harmless UI preferences |
| Analytics and reporting data | Hub manifests supplied for registration |
| RLS, API/RPC contracts and migrations | Integration with approved APIs |
| Hub registry and platform contracts | Declared platform compatibility |
| Administrative data boundary | No backend infrastructure |

## Layers and schemas

```text
Presentation
├── learner hubs
└── Central Admin Portal
          │
Application/API
├── api          learner-safe/public views and RPCs
└── admin_api    staff-only read boundary
          │
Domain/data
├── learning     identity, curriculum, delivery and evidence
└── platform     registry, contracts, roles, audit and health
          │
Identity
└── auth         Supabase Auth
```

`learning` and `platform` are protected implementation schemas. The public API
surface is not a synonym for direct table access.

## Trust boundary

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

## Compatibility and extraction

The original backend migration history remains unchanged so a future transfer
can preserve database objects, stable identifiers and learner history. New
changes are appended as forward migrations.

Hub repositories own their root `learning-platform-hub.json`. A reviewed copy
can be validated and converted to migration SQL here, or registered by an
authorised `platform_admin` through `admin_api.register_hub`, or updated
through `admin_api.update_hub`. Runtime registry
access terminates at the database and never reaches GitHub. See
`docs/hub-registration.md` for the controlled registration boundary.

Version 0.1.0 keeps every established learner API signature. The only behaviour
correction is assignment-aware multi-course submission resolution. A learner
with multiple active enrolments can submit when exactly one enrolled group owns
the activity assignment. Ambiguous assignment is rejected.

## Audit and operations

`platform.audit_events` is an append-only foundation for security-sensitive and
administrative events. `platform.operational_health` holds current service
health, with a safe projection from `api.platform_health()` and diagnostics
visible only to authorised staff.

No monitoring collector, alerting pipeline or automatic audit trigger is
claimed in this release.

## Known architectural debt

- Existing formative activities submit client-derived correctness and marks.
  The backend validates ranges and consistency and derives totals, but fully
  server-authoritative marking requires a versioned marking contract.
- Curriculum metadata does not yet implement every LHDS lifecycle and learning
  outcome field.
- Administrative writes require separately designed, audited RPCs.
- The hosted project migration-history handoff remains future release work.
