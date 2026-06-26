---
name: refactoring
description: Audit and modernize R scripts through iterative refactor passes.
---

# Refactoring

Enforce `snake_case`, `|>`, `<-`, explicit `return()`. Remove global state, add
`checkmate` validation, route errors through `cli`. Reduce duplication, separate
validation from transformation. Remove dead code and backward-compat scaffolding.

## Approach

1. **Analyze** — identify inefficiencies, redundant patterns, dependency/data-structure
   trade-offs.
2. **Refactor incrementally** — verify correctness after each step.
3. **Reassess** — performance, clarity, coverage, modularity. Repeat until no gains remain.
4. **Document** rationale for key changes.

## Splitting scripts

Split at ~300 lines (must split >500) or multiple responsibilities. Preserve numeric
prefixes for order; keep scripts grouped by stage.

## Constraints

No feature expansion. No API breaks unless modernization requires. Deterministic only.
