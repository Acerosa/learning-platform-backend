# Repository-driven hub registration (LHDS)

## Boundary and authority

Every learner hub repository must carry `learning-platform-hub.json` at its
repository root. The file describes the hub and its platform compatibility; it
must not contain curriculum activities, questions, learner data or secrets.

The reviewed repository manifest is the source used to prepare a registration
change. `platform.hubs`, `platform.hub_course_links` and
`platform.contract_versions` remain the authoritative runtime registry. No API,
view or database function fetches GitHub, and production never reads manifest
JSON from a repository at runtime.

The canonical JSON Schema is
`supabase/data/manifests/schemas/learning-platform-hub.schema.json`. It is the
Phase 1 Hub Manifest part of the Learning Hub Development Standard (LHDS).
Reviewed copies of the current manifests live under
`supabase/data/manifests/hubs/`; the legacy `hub-registry.json` snapshot links
to those copies and is cross-validated for compatibility. None of the current
hubs are represented as certified.

This backend phase does not modify learner-hub repositories. The reviewed
copies establish the shared contract; adding the matching root file to each
existing hub is a separate, hub-owned adoption change.

Unit 14 is registered locally as testing/active from
`supabase/data/manifests/hubs/unit-14-software-engineering-for-business/learning-platform-hub.json`.
Curriculum catalogue data is a separate content-package publication; see
[content-publication.md](content-publication.md). Hub Manifest 1.0.0 still
cannot hold a curriculum pointer.

## Manifest contract 1.0.0

| Field | Meaning |
| --- | --- |
| `manifestVersion` | Version of this manifest contract. |
| `hubId` | Immutable, lower-case kebab-case public hub identifier. |
| `name`, `description` | Human-facing, non-blank hub metadata. |
| `version` | Hub release version using Semantic Versioning 2.0.0. |
| `repositoryUrl`, `deploymentUrl` | Canonical HTTPS locations without query, fragment or trailing slash. |
| `courses` | One or more reviewed `learning.courses.stable_key` values. |
| `compatibility.required` | Exact required core, learner API and submission contract versions. |
| `compatibility.testedCombinations` | Tested version combinations; it must include the required combination. |
| `capabilities.evidence` | Generic evidence shapes the hub can submit, such as `question-level`. |
| `capabilities.activities` | Generic activity capabilities supported by the hub. |
| `featureFlags` | Boolean lower-camel-case feature declarations. |
| `certification` | Optional LHDS certification metadata. Omission means no certification claim. |

Unknown fields fail validation. Adding a common field requires a new reviewed
manifest-contract version rather than an ad hoc hub extension.

Compatibility values are exact versions in Phase 1. A version is registrable
only when its `hub-manifest`, `learning-platform-core`, `learner-api` and
`submission` rows are active in the reviewed platform contract catalogue and
in `platform.contract_versions` when the migration runs.

## Validation

Run:

```bash
python3 scripts/import/validate-hub-manifest.py \
  /path/to/hub-repository/learning-platform-hub.json
```

The dependency-free validator reports stable error codes and JSON paths. It
checks JSON ambiguity, schema fields and types, required fields, hub and course
naming, Semantic Versioning 2.0.0, HTTPS URL canonical form, unique arrays,
known courses, active platform versions, the tested compatibility combination,
and conflicts with reviewed hub IDs, repository URLs and deployment URLs.

Use `--json` for a machine-readable report suitable for the future Central
Admin workflow. Validation performs local file reads only; Phase 1 deliberately
does not accept a repository URL or fetch a remote manifest.

## Deterministic migration generation

After the manifest and repository change have been reviewed, generate SQL into
the non-runtime review area:

```bash
python3 scripts/import/generate-hub-registration-migration.py \
  /path/to/hub-repository/learning-platform-hub.json \
  supabase/data/generated/register-example-hub.sql
```

Generation validates before writing. New registrations default to `planned`
and inactive. An intentional lifecycle may be supplied with `--status`; the
`--active` flag is accepted only for `testing`, `production` or `maintenance`.

The output is deterministic for the same manifest and lifecycle arguments. It:

- derives the internal UUID with UUIDv5 from the immutable `hubId`;
- embeds the canonical manifest and its SHA-256 provenance hash;
- asserts active platform compatibility contracts and existing active courses;
- upserts descriptive hub metadata without replacing an existing internal ID;
- activates declared course links and deactivates links no longer declared;
- uses a transaction and a per-hub advisory lock.

The output must be reviewed, moved into a new timestamped migration, covered by
tests and applied through the normal release gates. The generator has no hosted
Supabase operation and never runs `db push`.

## Controlled registration workflow

```text
Hub repository
  -> learning-platform-hub.json
  -> local schema and conflict validation
  -> platform compatibility checks
  -> deterministic reviewed migration
  -> platform.hubs + platform.hub_course_links
  -> runtime registry/API
```

`platform.contract_versions` is the compatibility authority consulted by the
generated migration; a hub manifest cannot create or alter platform contract
versions.

## Future Central Admin integration

Phase 1 exposes contracts and a JSON validation report but does not implement
remote fetching, approval persistence or a mutation RPC. A later trusted
server-side workflow may accept a repository URL, fetch the root manifest once,
display this validation report, record administrator approval and prepare the
same reviewed migration data. It must use an allow-listed fetcher with timeout,
size and redirect limits and must never make GitHub part of normal learner or
admin runtime reads.
