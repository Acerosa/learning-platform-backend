# Published marking coverage restore — production results

**Project:** `hubwpkrqndorznwzvaer`  
**Applied:** 2026-11-27  
**Repository migration:** `20261127130000_restore_published_marking_coverage.sql`  
**Hosted migration version:** `20261127111520` (`restore_published_marking_coverage`)

**Foundations language-aware follow-up:** `20261127150000_foundations_language_aware_marking.sql` → hosted `20261127122144`

## Before → after unresolved published questions

| Hub | After PR #69 | After language-aware |
| --- | ---: | ---: |
| T Level Software Development | 25 | 0 |
| Unit 3 Cyber Security | 0 | 0 |
| Emerging Digital Technologies | 0 | 0 |
| Unit 14 Software Engineering | 0 | 0 |
| **Total** | **25** | **0** |

## What was restored (PR #69)

- Missing marking specs for Foundations activities with answer keys in the staff package (87 `question_marking` rows inserted; 2382 → 2469).
- Fingerprint refresh for T Level week-5 classification items and L2E single-choice items whose stored fingerprints no longer matched `published_question_fingerprint`.
- Unbound resolve preference for a unique automatic published spec when `requires_review` and automatic catalogue versions collide (`week6-legislation-matching` 1.0.0 → 1.2.0 `multi-field-exact`).

## Foundations language-aware marking (hosted `20261127122144`)

Root cause: staff/learner projection flattened `predict-output` / `code-gap` / `line-select` / `code-editor` items to empty `single-choice` blocks, so no automatic `question_marking` rows were registered. Authoritative answers live in T Level hub banks as language-specific `answers` / `rules` / `answer` fields.

Implemented:

- Marking mode `language-variants` resolved by `learning.marking_programming_language` (set from `api.submit_attempt`) or payload `programmingLanguage`.
- Exact and code-rule variants (POSIX regex via `platform.posix_js_pattern`); no unrestricted code execution.
- Restored 25 authoritative specs for `foundations-programming-diagnostic` 2.0.0 from hub banks.
- Publish-time enrichment from package language content before `MARKING_COVERAGE_INVALID`.
- Learner strip `lp.strip.v2` removes nested `answers` / `rules` / `answer` keys.
- Admin summary view includes `marking_mode` / `has_language_variants` (no answer keys).

Integrity after language-aware apply:

| Metric | Before | After |
| --- | ---: | ---: |
| attempts | 2026 | 2026 |
| responses | 8195 | 8195 |
| activity_states | 2508 | 2508 |
| publications | 180 | 180 |
| question_marking | 2469 | 2494 |
| unresolved published | 25 | 0 |

Verified marking: correct/incorrect feedback; JS-specific answers rejected for Python; missing language fails closed (`requires_review`).

Client hub banks remain for intentional Foundations formative UX; persisted scores use server-side `submit_attempt` marking. T Level curriculum was not republished.

## Integrity (PR #69 baseline)

| Metric | Before | After |
| --- | ---: | ---: |
| attempts | 2026 | 2026 |
| responses | 8195 | 8195 |
| activity_states | 2506 | 2506 |
| publications | 180 | 180 |
| question_marking | 2382 | 2469 |

## Rollback notes

- Function/view changes can be reverted by redeploying prior definitions from `20261127140000` / `20261127130000` / `20260924231428`.
- Inserted language-variants rows for the 25 FOUND-PROG keys would need an explicit delete list if rollback is required; do not bulk-delete marking.
- Do not disable fingerprint validation or weaken `MARKING_COVERAGE_INVALID` to roll back.
