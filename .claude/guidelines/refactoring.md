---
name: refactoring
description: Audit and modernize R scripts through iterative refactor passes.
---

# Refactoring

Use this when auditing and modernizing R scripts, dependencies, tests, or folder
structure. Apply the standards in [../../CLAUDE.md](../../CLAUDE.md) throughout.

## Mandatory actions

- Enforce `snake_case`, native pipe `|>`, `<-` assignment, explicit `return()`.
- Remove global state; add `checkmate` validation; route diagnostics/errors through `cli`.
- Reduce duplication; separate validation from transformation; improve modularity.
- Stabilize output schema; eliminate redundant normalization; guarantee idempotence.
- Remove unused dependencies; correct imports; fix `renv` inconsistencies.
- Remove dead code and backward-compatibility scaffolding wherever found.
- Improve test coverage alongside the change (see [testing.md](testing.md)).

## Iterative approach

Do not stop at the first correct solution — for non-trivial refactors, make multiple
passes:

1. **Analyze** the task in stages; identify inefficiencies, redundant patterns, and
   improvement opportunities. Reason through dependencies, data structures, and
   algorithmic trade-offs (memory, computation, readability, modularity).
2. **Refactor incrementally**, verifying correctness and deterministic behavior after each
   step.
3. **Reassess** after each pass — performance, clarity, coverage, modularity — and refine.
   Repeat until no further meaningful gains remain.
4. **Document** the rationale for each key change.

## Splitting long scripts

A script is too long when it exceeds ~300 lines (must split if >500), holds multiple
responsibilities (e.g. loading + processing + modeling), or is hard to follow due to size
or nesting.

When splitting:

- Preserve the pipeline naming logic: keep numeric prefixes for order, renumber as needed
  to maintain execution order, keep descriptive suffixes.
- Keep scripts grouped by pipeline stage.
- Do not rename files unless necessary for consistency.

## Constraints

- No feature expansion.
- No API breaking unless modernization requires it.
- No output-schema changes unless modernized behavior demands it.
- Deterministic, reproducible changes only.
