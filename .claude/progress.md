# Autocode Progress

## Current state

- **Tests:** 1007 passed / 0 failed (100%)
- **Postpro (120k subset):** 11.33s (baseline was 27.89s — 1.76x faster)
- **Import:** ~68s with auto-parallel (was 142s sequential — 2.1x faster)
- **Last session:** jun24 (branch `autocode/jun24`)

## Optimization boundaries

Hard limits discovered through profiling and experimentation. Future sessions should
read these before planning experiments.

- **Import is bounded by readxl C code.** The only safe lever is parallelism (already
  auto-enabled at `min(4, cores-1)` workers). A dependency swap to `openxlsx2`/`tidyxl`
  could unlock per-sheet parallelism but is out of scope without explicit approval.
- **Postpro rule application is inherent cost.** The hot path (footnote explosion/join/
  reconstruction over all rows, 4-pass rule application) has been vectorized and
  GForce-optimized. Remaining candidates are either sub-noise (<5%) or behavior-risky
  (pruning transitive rule cascades, cheaper cycle-detection hashes).
- **NA-row footnote skip is unsafe.** 4 of 537 footnote rules intentionally match
  NA/blank sources and update other columns — skipping NA rows would change output.
- **8 import workers is slower than 4.** I/O + serialization bound; returns diminish
  past ~4 workers.

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
