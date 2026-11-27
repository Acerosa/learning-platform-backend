# Historical marking-resolution impact (read-only)

**Project:** `hubwpkrqndorznwzvaer`  
**Captured:** 2026-11-27  
**Scope:** Aggregate counts only. No student rows were modified.

## Formative checks

| Metric | Count |
| --- | ---: |
| Total formative checks | 13 768 |
| `is_correct is null` | 1 113 |
| `requires_review` | 1 113 |
| Both null correct and requires review | 1 113 |
| Distinct learners | 87 |
| Date range | 2026-09-01 → 2026-11-27 |

Every null-correct formative check also has `requires_review=true`, matching the fail-closed behaviour when `resolve_marking_question` returned null.

## Assessment responses

| Metric | Count |
| --- | ---: |
| Total responses | 8 195 |
| `is_correct is null` | 511 |
| `requires_review` | 787 |

## Recovery options for learners

- Formative checks are append-only practice. Learners can check answers again after coverage restore; new checks use restored specs where available.
- Foundations programming-diagnostic language/code items still rely on hub-local banks when learner packages strip keys (hub PR #60).

## Remediation proposal (requires separate approval)

1. Do **not** bulk re-mark historical formative checks or assessment responses.
2. Optionally produce a staff-only report of activity keys / date ranges with elevated `requires_review` rates for tutor follow-up.
3. If grade-bearing assessment responses were affected, approve a targeted correction plan per course before any update.
4. Preserve existing attempt/response/progress rows unless an approved correction script is reviewed.
