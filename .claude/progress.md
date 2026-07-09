# Autocode Progress

## Current state

- **Tests:** 1007 passed / 0 failed (100%)
- **Dataset is GROWING (jul4):** the import folder went 729 → 1360 workbooks
  (601,766 long rows) with files still syncing in via Nextcloud **mid-session**.
  Cross-run comparisons of the official metric are confounded by data drift —
  freeze inputs before any A/B (jul4 used a local temp copy of the workbooks +
  the pinned `data/.autocode_bench/raw_dt.rds`, 360,798 rows).
- **Import (1360 workbooks, 8 workers):** ~70–85s on the live Nextcloud dir, ~72s
  on a frozen local copy after the jul4 wins (fused read+transform −11.8s,
  vectorized validation −9.3s, both measured isolated same-process).
- **Postpro (120k subset):** ~11.3s cached-import min-of-5 (full 357k ≈ 42s).
- **Export:** ~0.5s on the 120k subset. Unchanged.
- **Last session:** jul4 (branch `autocode/jul4`; carries the jun29 progress-bars
  work as its first commit)
- **Measurement noise:** the official `PIPELINE_SECONDS` metric has a ~10% run-to-run
  floor (cold first rep + worker spawn + Nextcloud-FS contention + antivirus scans of
  fresh files; postpro alone swings ±7% with no code change) **plus dataset drift**.
  Decide import experiments with a **same-process A/B on a frozen local workbook
  copy** and postpro experiments with the **cached-import bench**
  (`WHEP_BENCH_CACHE_IMPORT=1`, min of ≥5 reps) gated by the golden byte-identical
  verifier. A single official run can read as a false regression — never
  keep/discard on one reading.

## Post-merge checklist (after PR #127 and the audit-fix branch land on main)

1. Delete `data/.autocode_bench/raw_dt.rds` and rebuild (`WHEP_BENCH_CACHE_IMPORT=1`)
   — the pinned snapshot is 360,798 rows; the live dataset is 601k+ and growing.
2. Re-capture all perf verify goldens on the merged main — the audit fix
   intentionally changes 4 clean-audit rows, so pre-merge goldens false-fail.
3. Re-baseline `PIPELINE_SECONDS` before the next session; numbers in this file
   predate the dataset growth.

## Optimization boundaries

Hard limits discovered through profiling and experimentation. Future sessions should
read these before planning experiments.

- **Import is bounded by readxl C code (~95%: `.External` parse + `unz` + tibble→df).**
  The only safe lever is parallelism, auto-enabled at `min(import_parallel_workers_auto_max,
  cores-1)`. A dependency swap to `openxlsx2`/`tidyxl` was probed and **rejected** —
  readxl's exact text rendering (e.g. numeric year headers) is what the pipeline is
  calibrated to; a swap changes outputs and fails the byte-identical gate.
- **8 workers is the import optimum on a 16-core box — NOT slower than 4 (jun24 note
  refuted).** Sweep (729 workbooks, 16 cores): seq 89.5s → 4w 42.5s → **8w 38.3s** →
  12w 44.6s (regresses). Interleaved A/B: 8w is −3.9% vs 4w in every rep, byte-identical.
  `auto_max` is now `8L`. The prior "8 slower than 4" was measured on fewer cores.
- **Import workbook batch size is sub-noise.** Interleaved A/B at 8 workers: batch
  16/8/4 vs 32 all land within ~1–2.5% (below the 5% noise threshold). Left at 32.
- **Postpro rule application is inherent cost.** Footnote explosion/join/reconstruction
  and the 4-pass clean loop are vectorized + GForce-optimized. **Multi-pass trigger-column
  pruning is low-reward AND risky (re-confirmed jun26):** the 7 clean rule files / 4241
  rules use ALL 9 data columns as source *and* target *and* target-condition, so pass 1
  dirties every column → the trigger set is ~all columns → nothing to prune. Passes
  genuinely need 4 iterations (581k→76k→16k changes→converge).
- **Postpro rule-loading (~24% of the 120k metric) is largely a benchmark artifact.**
  The bench disables `runtime_cache` for stable timing, so it re-reads rule xlsx every
  run; in production the cache defaults ON (disk→memory), so it is a one-time cold cost.
  Don't optimize the uncached path to game the metric.
- **Convergence-signature `serialize()` can't use the mutable-columns trick** — clean
  rules target all columns, so "mutable columns" = all columns. No saving.
- **NA-row footnote skip is unsafe.** Some footnote rules intentionally match NA/blank
  sources and update other columns — skipping NA rows would change output.
- **NA-footnote DEDUP changes audit counts (jul4).** `strsplit(NA_character_)` already
  emits one NA token, so the `na_rows` append in `apply_footnote_rules` duplicates
  every NA-footnote row (76% of rows) through the rules join. Removing it leaves the
  harmonize/clean/normalize DATA byte-identical but **halves `affected_rows` on 4
  clean-audit rows** (audit currently double-counts NA rows — latent bug, spun off as
  a separate fix task). Only the sort-skip fraction was kept (exp-B2).
- **Rule-dictionary hoisting is dead (jul4, measured).** Rebuilding the conditional
  rule dictionary costs 0.08s across all 4 passes × 7 payloads — not worth plumbing
  `prepared_payload` through the layer runner (which would also have to guard against
  `apply_conditional_rule_group` mutating `group_dt` by reference across passes).
- **Per-column join-key encode caching: small (jul4, measured).** Dataset-side
  `encode_rule_match_key` per source column is 3–13ms @120k (cardinality-aware
  normalization); ~16 groups × 4 passes ≈ 0.4–0.6s total. Possible with
  changed-columns invalidation, but low reward vs. staleness risk.
- **The official metric's rule-loading share is inflated by design.** The bench
  disables `runtime_cache`/schema cache, so every postpro run re-reads rule xlsx
  (~2s @120k, also re-read inside `persist_postpro_audit`); production caches them.
  Passing loaded payload bundles into persist would only game the bench — skipped.

## Session archive

### jul4 — import main-process overhead eliminated; postpro cycle-detection lazy

Fresh profile on the grown dataset (1360 workbooks / 601,766 rows — +87% since
jun26) found the real headroom had moved to the import **main process**, not readxl:
per-document validation looped 1360 × (table copy + `Sys.Date()` timezone lookup +
per-row error pasting), and the two-stage read→transform re-exported the whole
`read_data_list` to the transform workers (~11.6s of serialize). All experiments
gated on frozen inputs (local workbook copy + pinned raw_dt.rds) with byte-identical
verifiers covering data, audits, overwrites, multipass diagnostics, and all 418,825
validation-error strings.

- **exp-A (keep): one reference year per run.** `validate_year_values` resolved
  `Sys.Date()` per document (Windows tz-database lookup each call). Isolated
  validation step 9.27s → 4.56s (−51%).
- **exp-B (discard → spun off):** deduping the NA-footnote rows is data-identical but
  halves 4 clean-audit `affected_rows` (see boundaries) — filed as a correctness fix,
  not a perf keep. **exp-B2 (keep):** drop the `setkey` re-sort (order provably
  unobservable); perf-neutral hygiene.
- **exp-C (keep): lazy stage-state records.** Multi-pass cycle detection serialized
  the full table every pass; now a sound fingerprint + column-pointer copy, exact
  serialize only on fingerprint collision (verdict-preserving by construction).
  86ms → 20ms per state @120k (×3 @full); stored state 25MB → 10MB per pass.
  Sub-noise in the official bench.
- **exp-E (keep, biggest single win): vectorized per-document validation.**
  `validate_long_dt_by_document()` reproduces split-by-document semantics globally —
  same rows document-major, same 418,825 error strings in the same order (8
  adversarial fixtures incl. non-contiguous docs). Isolated step 9.99s → 0.65s
  (−93%). Old per-table validators unchanged for their contract tests.
- **exp-D (keep): fused read+transform batches.** `read_transform_pipeline_files()`
  reads + transforms per batch in the worker; read data never round-trips. Same-process
  A/B (fused arm cold): 81.4s → 69.6s (−14.5%); output identical incl. 15 real read
  errors. Progress budget (2n+4) preserved; ticks interleave per batch now.
- Combined isolated import savings ≈ −21s on the frozen copy (~−25% of import);
  postpro ~−0.4s @120k (~−1.3s full) + memory.

**jul4 bug-hunt round** (three parallel adversarial sweeps over the modules the
perf loop never touched; every finding re-verified by trace before acting):
- **Fixed:** locale-dependent `sort()` on export column names
  (`normalize_for_comparison`, `collect_union_columns` → `method = "radix"`,
  matching the documented determinism contract); latent duplicate-column guard in
  `resolve_canonical_header_renames` (two aliases → one target).
- **Spun off (behavior changes needing sign-off):** checkpoint staleness — RDS
  checkpoints are keyed by static name with NO input/config invalidation; on this
  live-growing dataset an opt-in user gets silently stale imports (chip
  task_6fd14092). Earlier: clean-audit NA double-count (fixed in a parallel
  session, branch `claude/nervous-vaughan-58e3e8`).
- **Refuted after trace (agents' claims that didn't survive):** header-collision
  primary scenario (the `c(header_names, new_names)` guard already blocks it);
  standardize "all-NA groups become string NA" (`as.character(NA_real_)` is
  `NA_character_`); revert-sequencing bug (not live); melt drops are mitigated by
  `setcolorder`; `sort_pipeline_stage_dt` already radix via `setorderv`.
- **Blocked by read-only tests:** `cached_unzip` (10 explicit source refs in
  `tests/`+`perf/`) and `generate_export_path` (contract test) are pipeline-dead
  but cannot be removed — annotated dead/pinned in the codebase map.
- **Measured lean (no action):** import tail at 601k = drop_na 0.0 + validate 1.2
  + consolidate 0.06 + sort 0.23 ≈ 1.5s; postpro audit 0.66 / standardize 0.62 @120k.


Condensed record of past autocode sessions. See `results.tsv` for the full experiment
ledger with per-commit scores.

### jun18 — correctness (506/41 → 975/0)

Fixed 41 test failures: eager `source_postpro_scripts()` at module load (+415 passes),
rule engine fixes (+26), constants/config alignment (+8), code quality cleanup. Final 2
failures were contradictory read-only test assertions — aligned with authoritative
behavior. Also migrated processed export from xlsx to TSV (exp-17).

### jun22 — postpro performance (27.89s → 21.11s, -24%)

Vectorized footnote long-format explosion (-23%), cardinality-aware semicolon
canonicalization (dropped out of hot list). Full-dataset validation: postpro 60.36s →
42.29s (-30%), output content-identical. Added opt-in import parallelism flag
(`whep.import.parallel_workers`).

### jun24 — postpro + import performance (21.83s → 11.33s postpro, import ON by default)

GForce footnote reconstruction (-23%), rule-engine micro-optimizations, deferred
last-rule-wins collapse (-36%). Exhaustive 72-candidate search confirmed remaining
opportunities are sub-noise or behavior-risky. Import parallelism changed to auto-on
by default (142s → 68s). Combined: ~halved full-pipeline wall-clock.

### jun26 — fresh full-pipeline re-profile; import worker cap 4→8

Re-profiled from scratch. Confirmed split: import ~70% of metric, postpro ~30%, general
negligible (0.16s). One substantive win plus a hygiene change; the rest of the search
space was exhausted and documented under "Optimization boundaries" with fresh evidence.
- **exp-1 (keep, the real win): import auto worker cap 4→8.** Worker sweep + interleaved
  A/B on 16 cores show 8 is the optimum (−3.9% import, ~−2.7% pipeline), byte-identical
  to 4w on the full 360,798-row import. Refutes the jun24 "8 slower than 4" note.
- **exp-2 (keep, hygiene/perf-neutral): postpro audit tree was created twice per run**
  (step 2 + step 3); step 2 now resolves paths only. Byte-identical, tests 1007/0.
  Isolated cost of the removed call ≈ 5ms (kept as redundant-work removal, not a perf win).
- **exp-3 (keep): export builds the unique-value cache only for exported columns.**
  It was computing `unique()+sort()` over the full column union — including the
  high-cardinality `value` (and `year`) which are never written — across all four
  layers. Isolated unique-cache build −46% (0.205s→0.110s). Byte-identical export
  output (10 `unique_*.xlsx` + TSV read back from disk on the full 357k layers).
  Export is ~1–3% of the pipeline, so the absolute saving is ~0.1s.
- **Export brought into scope (metric change):** `autocode_bench.R` now times
  `run_export_pipeline` on the postpro layers and includes it in `PIPELINE_SECONDS`
  (+`EXPORT_SECONDS` diagnostic), writing to a gitignored bench dir. Profiling
  confirmed export is small even on the Nextcloud FS (writes are tiny + one fast
  `fwrite`), so there is little headroom — `value`/`year` cache skip was the only
  clear waste. New gate `perf/_verify_export.R` reads written files back and compares.
- **Ruled out with evidence:** batch-size tuning (sub-noise), >8 workers (regress),
  reader swap (breaks byte-identical), multi-pass pruning (dense column interdependence
  → no prunable set), rule-loading (cached in prod), convergence-serialize mutable-cols
  trick (clean targets all columns). See boundaries above.
- New scratch harnesses (gitignored `perf/_*.R`): `_ab_workers.R`/`_ab_batch.R`
  (interleaved import A/B), `_verify_import.R` (import byte-identical gate),
  `_diag_passes.R` (multi-pass pruning potential).
