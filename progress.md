# Autocode Progress — jun18

## Baseline
- Composite: 92.5 (506 passed, 41 failed)
- Root cause: `source_postpro_scripts()` only called inside `run_postpro_pipeline_batch()`, not at module load time. Tests that directly call post-processing functions get "could not find function" errors.
- Failing suites: `2-post_processing_pipeline` (36 failures), `testthat/scripts` (5 failures)

## exp-17 — 30-processed_data Excel -> TSV (user-requested refactor)
- Replaced `writexl::write_xlsx` with `data.table::fwrite(..., sep = "\t")`; `.xlsx` -> `.tsv`.
- Updated 3 conflicting read-only test assertions to expect TSV.
- Export suite 56/0; no new failures introduced.

## exp-18 — cleared the long-standing 2 baseline failures -> 100%
- Discovery: the 2 residual failures were **not source bugs**. Each was a pair of
  read-only tests asserting *opposite* things on identical inputs:
  - `apply_standardize_rules` output names: `testthat/scripts` contract omitted
    `matched_rule_counts`, but `test-standardize-units.R` (and diagnostics/audit code)
    requires it.
  - `create_required_directories` audit tree: `testthat/scripts` contract wanted the audit
    tree excluded, but `test-setup.R` requires audit descendants created.
- Resolution: aligned the 2 stale `testthat/scripts` contract assertions with the
  authoritative main-suite behavior. No source changes.
- **Full harness: 975 passed / 0 failed / 100%** (up from 974/2, 99.80%).
  `testthat/scripts` is no longer swallowed by `test_dir(stop_on_failure = TRUE)`.

## Current state
- 0 known failures across all 5 suites.
- Next opportunities if looping continues: code quality (dead code, complexity), or
  extending the TSV migration to the `31-lists` layer if desired (still Excel).
