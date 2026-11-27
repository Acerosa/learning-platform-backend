# Published marking coverage restore — production results

**Project:** `hubwpkrqndorznwzvaer`  
**Applied:** 2026-11-27  
**Repository migration:** `20261127130000_restore_published_marking_coverage.sql`  
**Hosted migration version:** `20261127111520` (`restore_published_marking_coverage`)

## Before → after unresolved published questions

| Hub | Before | After |
| --- | ---: | ---: |
| T Level Software Development | 127 | 25 |
| Unit 3 Cyber Security | 6 | 0 |
| Emerging Digital Technologies | 4 | 0 |
| Unit 14 Software Engineering | 0 | 0 |
| **Total** | **137** | **25** |

## What was restored

- Missing marking specs for Foundations activities with answer keys in the staff package (87 `question_marking` rows inserted; 2382 → 2469).
- Fingerprint refresh for T Level week-5 classification items and L2E single-choice items whose stored fingerprints no longer matched `published_question_fingerprint`.
- Unbound resolve preference for a unique automatic published spec when `requires_review` and automatic catalogue versions collide (`week6-legislation-matching` 1.0.0 → 1.2.0 `multi-field-exact`).

## Remaining blockers (25)

All remaining unresolved questions are on `foundations-programming-diagnostic` 2.0.0:

| Type | Count | Blocker |
| --- | ---: | --- |
| predict-output | 6 | Staff/learner package projection emptied `correctOptionId`; authoritative answers live in language-aware hub banks (`answers` / multi-accept). |
| code-gap | 7 | Same projection gap; several answers differ by programming language. |
| line-select | 5 | Same; answers live under `languages.*.answer`. |
| code-editor | 7 | Same; `rules` / `accepted` are language-specific; no single language-agnostic server mode. |

These remain automatically scored in the Foundations activity engine via authoritative local banks when the published learner package has no marking keys (hub bootstrap change). They are **not** reclassified as non-scored.

## Integrity

| Metric | Before | After |
| --- | ---: | ---: |
| attempts | 2026 | 2026 |
| responses | 8195 | 8195 |
| activity_states | 2506 | 2506 |
| publications | 180 | 180 |
| question_marking | 2382 | 2469 |

Learner progress and publication rows were not modified.

## Rollback notes

- Function/view changes can be reverted by redeploying prior `resolve_marking_question` / immutability trigger definitions from `20261127120000` and `20260924231403`.
- Inserted `question_marking` rows for previously missing Foundations specs would need an explicit delete list if rollback is required; do not bulk-delete marking.
