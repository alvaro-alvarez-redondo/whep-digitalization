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

## jun22 — performance loop (speed & responsiveness)

Goal: highest-value, behavior-preserving speedups. Branch `autocode/jun22`.

### Audit (profiled the real pipeline on 754 workbooks → 360,798 rows)
- general 2.6s · **import 84s** (I/O-bound: readxl unzip+parse+name-repair) ·
  **postpro 68s** (CPU-bound, pure R) · total ~155s.
- Import is bounded by `readxl` C code → not safely optimizable without a
  dependency swap or parallelism (both out of scope: behavior/determinism risk).
- Postpro is the target. Function-level hot spots:
  - `apply_footnote_rules` ~53% of postpro.
  - `canonicalize_semicolon_delimited_cells` ~15% (per-cell `vapply`).

### Metric
- `[metrics.tests]` (weight 0.5, correctness gate — must stay 975/0) +
  `[metrics.performance]` (weight 0.5): `perf/autocode_bench.R` times
  `run_postpro_pipeline_batch` on a 120k-row deterministic subset of the real
  imported data (min of 2 reps). Lower is better. Import output cached under
  gitignored `data/.autocode_bench/`.
- Baseline: tests 975/0; **postpro_s = 27.89** (subset). Run-to-run noise ~8%.

### Experiments
- exp-1: vectorize footnote long-format explosion (drop the per-row `by=row_id`
  grouping + double strsplit). Byte-identical output verified across edge cases.

## Current state
- 0 known failures across all 5 suites.
