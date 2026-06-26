# Autocode Progress

## Current state

- **Tests:** 1007 passed / 0 failed (100%)
- **Import (full, 729 workbooks):** ~38–40s at the new 8-worker default (was ~42s
  at 4 workers — interleaved A/B: −3.9%). Sequential is ~89s.
- **Postpro (120k subset):** ~11.5s (full 357k ≈ 42s).
- **Last session:** jun26 (branch `autocode/jun26`)
- **Measurement noise:** the official `PIPELINE_SECONDS` metric has a ~10% run-to-run
  floor (cold first rep + worker spawn + Nextcloud-FS contention; postpro alone swings
  ±7% with no code change). Decide import experiments with an **interleaved A/B in one
  process** (`perf/_ab_*.R`) and postpro experiments with the **cached-import bench**
  (`WHEP_BENCH_CACHE_IMPORT=1`, min of ≥5 reps). A single official run can read as a
  false regression — do not keep/discard on one reading.

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

## Session archive

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
- **Ruled out with evidence:** batch-size tuning (sub-noise), >8 workers (regress),
  reader swap (breaks byte-identical), multi-pass pruning (dense column interdependence
  → no prunable set), rule-loading (cached in prod), convergence-serialize mutable-cols
  trick (clean targets all columns). See boundaries above.
- New scratch harnesses (gitignored `perf/_*.R`): `_ab_workers.R`/`_ab_batch.R`
  (interleaved import A/B), `_verify_import.R` (import byte-identical gate),
  `_diag_passes.R` (multi-pass pruning potential).
