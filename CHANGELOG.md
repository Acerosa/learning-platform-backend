# Changelog

All notable changes to the Learning Platform Backend are documented here.

The project follows Semantic Versioning.

## [Unreleased]

### Added

- LHDS `learning-platform-hub.json` schema and reviewed manifests for both
  current learner hubs.
- Dependency-free hub validation with conflict, course, naming, Semantic
  Versioning and platform compatibility checks.
- Deterministic, inactive-by-default hub registration migration generation.
- First-class manifest/core/API/submission compatibility metadata, provenance
  hashes, URL uniqueness and database enforcement for hub registrations.

### Changed

- The legacy aggregate hub metadata entries now link to and are cross-validated
  against the standard hub manifests without breaking their existing shape.
- Platform contract fixtures include active hub-manifest and core versions.

## [0.1.0] - 2026-08-11

### Added

- Dedicated platform backend repository and local Supabase project identity.
- Complete 18-migration source history extracted unchanged from the T Level
  Digital Software Development Hub.
- Existing learner identity, curriculum, assignment, attempt, response,
  progress, analytics, registration and onboarding services.
- Protected `platform` schema for hubs, contract versions, staff roles, audit
  events and operational health.
- RLS-protected, read-only `admin_api` foundation for the Central Admin Portal.
- Safe hub discovery, contract-version and public-health RPCs.
- Draft hub registry entries for both current learner hubs.
- Database, RLS, API and integration test directories and new foundation tests.
- Repository validation, curriculum import tooling and release documentation.

### Changed

- `api.submit_attempt` now resolves the single matching assignment across all
  active enrolments instead of requiring exactly one active enrolment.

### Security

- Platform administrator access derives from Supabase Auth and protected staff
  roles.
- Learner and ordinary teacher sessions cannot read platform-wide admin data.
- Audit and operational writes are restricted to the service role.

### Deliberately excluded

- Hosted Supabase deployment or project linking.
- Administrative mutation RPCs.
- Server-authoritative marking redesign.
- Changes to either existing learner hub repository.
