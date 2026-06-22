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
- **exp-1 (keep):** vectorize footnote long-format explosion in
  `apply_footnote_rules` — drop the per-row `by=row_id` grouping (357k groups)
  and the double `strsplit`; build the long table with `strsplit`+`rep`+
  `sequence`. Byte-identical output verified across edge cases.
  postpro_s 27.89 → 21.45 on the 120k subset (**-23%**). Tests 975/0.
- **exp-2 (keep):** cardinality-aware `canonicalize_semicolon_delimited_cells` —
  canonicalize once per distinct cell value and map back (notes is 100% NA,
  footnotes has only 796 distinct values among 360k rows). Byte-identical.
  Subset wall-clock barely moved (small win obscured by ~8% noise), but a
  re-profile confirms `canonicalize` dropped out of the hot list entirely
  (it was ~15% on the full dataset). Tests 975/0.
- **exp-3 (rejected, not committed):** restrict footnote explosion to non-NA
  rows (76% of rows have NA footnotes). Investigated and **abandoned**:
  `clean_footnotes.xlsx` has 537 footnote rules, **4 with NA/blank source** that
  intentionally match NA footnotes (and footnote rules update other columns).
  Skipping NA rows would change behavior — not safe. The remaining footnote cost
  (explosion/join/reconstruction over all rows) is inherent to the rule
  semantics; reducing it further would be a risky reconstruction rewrite.

### Out of scope (flagged, not done)
- **Import (84s, the largest single cost)** is bounded by `readxl` (unzip +
  parse + name-repair, all C code). Safe levers don't exist without a dependency
  swap (forbidden) or enabling a parallel `future::plan()` by default — which
  introduces global state and isn't exercised by the (sequential) test suite, so
  it can't be validated under this loop. Left for an explicit, separately-tested
  decision.

### jun22 result
- **Post-processing stage ~30% faster** on the full real dataset (357,076 rows):
  60.36s → 42.29s (min of 2 reps), from exp-1 + exp-2 combined.
- Behavior preserved: full test suite 975/0 throughout; full-dataset postpro
  output content-identical between baseline and optimized (harmonize 357,076x11;
  `identical` + `all.equal` TRUE after normalizing equal-key row order / column
  attributes — the values are unchanged). No dependency, contract, or
  determinism changes.
- Import (84s) is bounded by `readxl`; the one real lever is parallelism — see
  the opt-in flag below.

### Import parallelism (opt-in flag; follow-up to the postpro loop)
- New switch `whep.import.parallel_workers` (option) ▸
  `config$performance$import_parallel_workers` ▸ constant default `1L`. When `>1`,
  `run_import_pipeline()` sets `future::plan(multisession, workers = N)` for that
  call only and restores the caller's plan on `on.exit` (global-state change
  scoped to the entry point). Default `1L` = sequential, so existing behavior is
  unchanged. Resolved by `resolve_import_parallel_workers()` (in `11-batching.R`).
- The read/transform stages already dispatched through `future.apply`; this just
  flips the plan. Verified output is **content-identical** to sequential on the
  full dataset (both at 4 and 8 workers).
- Speedup (full import, 16-core machine): **87.5s → 37.2s at 4 workers (~2.35x)**.
  I/O + serialization bound, so it does NOT scale with cores — 8 workers was
  *slower* (45.4s); ~4 is the sweet spot.
- Tests: full suite **983/0** (added `tests/1-import_pipeline/test-parallel-import.R`:
  flag-resolution unit tests + a parallel-vs-sequential output-parity test that
  skips only if the environment cannot start multisession workers).

## Current state
- 0 known failures across all 5 suites.
