---
name: testing
description: Generate or refactor testthat tests for modified or exported R functions.
---

# Testing

Use this when adding or updating tests. Every behavior or contract change ships with
tests. Suite locations and the enforced contracts are in
[../docs/architecture.md](../docs/architecture.md).

## Required test types

- Happy path
- Edge case
- Error case
- Legacy-elimination — assert that removed backward-compatibility behavior is gone

## Constraints

- Use `testthat`.
- Deterministic execution: no network or filesystem side effects; seeded randomness only.

## Implementation

- Create or update test files directly; aim for coverage completeness.
- Run the full suite before committing:
  `source(here::here("tests", "testthat", "test_all.R"), echo = FALSE)`.
- Never accept a change that lowers the test pass rate.
- Commit changes.
