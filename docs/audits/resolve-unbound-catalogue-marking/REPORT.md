# Resolve unbound catalogue marking

## Problem

Learners receive no correct/incorrect feedback when formative checks cannot
resolve a marking specification. Backend returns `requires_review=true` with
`is_correct=null`, and the UI shows a non-scored / informative state.

## Root cause

Hosted `learning.resolve_marking_question` lacked the unbound catalogue
fallback present in the prepared repository fix. Published package activity
versions (often `1.0.0`) do not carry their own `question_marking` rows when
Batch B registered specs on a later catalogue version (e.g. `1.1.0`).

Fingerprint binding alone does not recover these rows when
`sourceQuestionId` aliases diverge.

## Phase A / B contribution

None. Marking uses authoritative `learning.question_marking`, not learner
packages. Sanitisation correctly strips keys from public packages.

## Production impact (pre-fix)

| Hub | Questions in published package | Unresolved |
| --- | ---: | ---: |
| Unit 3 | 668 | 301 (all unbound) |
| T Level | 888 | 127 (112 no specs at all; 15 own fingerprint mismatch) |
| L2E | 496 | 4 |
| Unit 14 | 96 | 0 |

Simulated unbound fallback: Unit 3 newly resolves **295** questions.
T Level / L2E unresolved counts unchanged by this fallback (separate gaps).

## Fix

Migration `20261127120000_resolve_unbound_catalogue_marking.sql` adds a
fail-closed fallback: if exact-version and fingerprint rules miss, use the
**single** published marking spec for the same activity + question key.
