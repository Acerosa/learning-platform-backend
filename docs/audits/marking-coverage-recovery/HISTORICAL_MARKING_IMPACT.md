# Historical marking-resolution impact (read-only)

**Project:** `hubwpkrqndorznwzvaer`  
**Captured:** 2026-11-27 (refined same day)  
**Scope:** Aggregate counts only. No student rows were modified. No automatic re-marking.

## Classification

| Class | Definition | Formative checks | Attempt responses (`learning.responses`) | Diagnostic responses |
| --- | --- | ---: | ---: | ---: |
| Scored correct | `is_correct = true` | 9 604 | 6 335 | 101 |
| Scored incorrect | `is_correct = false` | 3 062 | 1 349 | 19 |
| Confirmed historical marking failures | `is_correct is null` **and** `requires_review = true` (fail-closed when `resolve_marking_question` returned null) | 1 113 | 511 | — |
| Intentionally non-scored / manual review with a score | `requires_review = true` **and** `is_correct is not null` | 0 | 276 | — |
| Null without review flag | `is_correct is null` **and** `requires_review` is not true | 0 | 0 | 19 |
| **Total rows** | | **13 779** | **8 195** | **139** |

Notes:

- Formative null-correct rows are exactly the fail-closed set (`1 113` / `1 113`); there are no formative nulls without `requires_review`.
- Attempt responses: `511` fail-closed nulls; `276` additional `requires_review` rows already carry a score (legitimate manual-review / non-auto path). Total `requires_review` on attempts = `787` (`511 + 276`).
- Diagnostic nulls (`19`) lack a `requires_review` column in the current schema; treat as unresolved diagnostic outcomes pending staff classification, not auto-remediation.

## Learner recovery paths (no historical rewrite)

| Class | Recovery |
| --- | --- |
| Formative fail-closed (`1 113`) | Learners can re-check; new formative checks use restored specs. Append-only; history unchanged. |
| Attempt fail-closed (`511`) | May include grade-bearing work. **Do not** bulk re-mark. Requires separate per-course approval if retrospective correction is desired. |
| Manual-review with score (`276`) | Leave in place; these are not unresolved-spec failures. |
| Foundations language items | New submissions use server `language-variants` (hosted migration `20261127122144`). Hub banks remain formative UX only. |

## Remediation proposal (requires separate approval)

1. Do **not** bulk re-mark historical formative checks or attempt responses.
2. Treat formative fail-closed rows as recoverable by learner retry; no grade correction script.
3. For the `511` attempt fail-closed rows, produce a staff-only activity/date report and approve a targeted correction plan per course before any update.
4. Preserve existing attempt/response/progress rows unless an approved correction script is reviewed.
5. Do not conflate the `276` scored manual-review attempt rows with historical unresolved-spec failures.
