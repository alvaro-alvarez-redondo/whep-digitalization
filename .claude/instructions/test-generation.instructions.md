---
name: test-generation
description: 'Generate or refactor tests for all modified or exported R functions.'
---

## Required Test Types
- Happy path
- Edge case
- Error case
- Legacy behavior elimination (**to ensure backward compatibility is removed**)

## Constraints
- Deterministic execution; no network or filesystem side effects.
- Seeded randomness only.
- Use `testthat`.

## Implementation
- Create or update test files directly.
- Ensure coverage completeness.
- Commit changes.