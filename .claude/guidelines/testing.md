---
name: testing
description: Generate or refactor testthat tests for modified or exported R functions.
---

# Testing

Every behavior/contract change ships with tests. Use `testthat`. Required types: happy
path, edge case, error case, legacy-elimination. Deterministic: no network/filesystem
side effects; seed randomness.

Run the full suite via `autocode.toml` `[metrics.tests]`. Do **not** use
`tests/testthat/test_all.R` (broken). Never accept a change that lowers pass rate.
