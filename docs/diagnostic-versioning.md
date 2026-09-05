# Diagnostic versioning policy

Readiness diagnostics are versioned independently of hub software version and
content-package version. `api.start_diagnostic` binds each sitting to
`platform.hubs.features.diagnosticVersion` at start time. Clients must not send
a version. A learner who refreshes or continues an existing sitting keeps that
bound version and must not silently switch specs.

## When to bump

| Change | Version |
| --- | --- |
| Wording-only or non-semantic correction that does not change meaning, options, or marks | Patch (`x.y.z+1`) is allowed |
| Correct answer, option set, or marking mode changes | New minor or major version required |
| Adding or removing questions | New version required |
| Changing marks or weighting | New version required |
| Changing question identifiers (`activity_id` / `question_key`) | New version required |

A material change to the question set, scoring contract, or denominator
requires a new diagnostic version. The current 25-question OCR Level 3 IT Year 1
readiness contract is `1.1.0` (maximum 24 scorable marks). Historical 14-question
sittings remain `1.0.0` until a separately approved historical spec exists.

## Marking

Authoritative marks live in `learning.diagnostic_question_marking`, keyed by
`(diagnostic_key, diagnostic_version, activity_id, question_key)`. Specs are
not granted to learners. `api.submit_diagnostic_response` marks against the
**session** version. Unknown versions stay unmarked (`is_correct` null, no
awarded score). Learner-facing RPCs never return scores or answer keys.

Do not seed a new question set under an old version. Do not relabel hosted
sittings without an explicit backfill approval.
