---
name: best-practices
description: 'Enforce commodityion-grade R script standards.'
---

## Mandatory Actions
- Enforce naming consistency, remove typos and inconsistent terminology.
- Remove duplicated logic; separate validation from transformation.
- Remove redundant normalization; optimize joins; guarantee idempotence.
- Standardize diagnostics; deepen input validation; improve error messaging.
- Reduce nesting; ensure deterministic behavior.
- Remove backward compatibility constraints; update legacy behavior.
- Remove unused code; optimize performance; enhance maintainability.
- Split long scripts into smaller ones with a single responsibility.

## Constraints
- No feature expansion.
- No API breaking unless required for modernization.
- No output schema changes unless modernized behavior demands it.

## Implementation
- Refactor scripts directly and commit changes.