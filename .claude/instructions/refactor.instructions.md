---
name: refactor
description: 'Perform full repository audit and implement refactors.'
---

## Purpose
Audit and modernize all R scripts, dependencies, tests, and folder structure. Fix any legacy patterns.

## Mandatory Actions
- Enforce `snake_case`, native pipe `|>`, `<-` assignment.
- Remove global state; add `checkmate` validation; explicit `return()`.
- Reduce duplication; improve modularity
- Stabilize output schema.
- Remove unused dependencies; correct import; fix `renv` inconsistencies.
- Improve test coverage.
- Eliminate backward compatibility constraints.

## Script Length Criteria
A script is too long if:
- It exceeds ~300 lines (must split if >500).
- It contains multiple responsibilities (e.g., loading, processing, modeling).
- It is hard to read or follow due to size or nesting.

When splitting scripts:
- Preserve the existing pipeline naming logic:
  - Keep numeric prefixes to indicate order.
  - Renumber scripts as needed to maintain execution order.
  - Keep descriptive suffixes.
- Keep scripts grouped by pipeline stage.
- Do not rename files unless necessary for consistency.