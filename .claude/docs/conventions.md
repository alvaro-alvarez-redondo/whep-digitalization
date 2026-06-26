# Conventions & gotchas

## Running the pipeline

```r
source(here::here("r", "run_pipeline.R"), local = TRUE)
run_pipeline(show_view = FALSE, pipeline_root = here::here("r"))
```

Sourcing `run_pipeline.R` **auto-runs** unless `whep.run_pipeline.auto` is `FALSE`.

## Running tests

Use the `autocode.toml` `[metrics.tests]` command, which sources `tests/test_helper.R`
and runs all five suite dirs:

```
tests/0-general_pipeline/  tests/1-import_pipeline/  tests/2-post_processing_pipeline/
tests/3-export_pipeline/   tests/testthat/scripts/
```

`test_helper.R` disables all auto-run options/checkpointing, sources general-stage
scripts, and defines fixtures (`build_temp_dir`, `build_test_config`, `create_test_xlsx`,
`build_sample_long_dt`). Per-stage test files source their stage runner.

> **`tests/testthat/test_all.R` is broken** — references non-existent `tests/testthat/r/`.

`tests/testthat/scripts/` holds **contract tests** that re-assert critical API shapes
independently. They run *in addition to* per-stage suites.

## Loading & source order

- No R package — everything `source()`d. Order matters.
- `01-constants.R` loads first. Then config → directories → helpers (alphabetically).
- `source_postpro_scripts()` runs at module load (bottom of `run_postpro_pipeline.R`),
  loading the entire post-processing stage.

### Adding a script

- **General-stage:** drop file with `0X-` prefix in the right subdir — sourced
  alphabetically, no constants change needed.
- **Stage 1/2/3:** new file in existing subdir is auto-discovered. New *subdirectory*
  must be added to the runner's subdir vector. Post-processing order is non-numeric:
  `20, 21, 23, 22, 24, 25` (rule engine before clean/harmonize).
- **New stage runner:** update `constants$script_names$pipeline_stage_runners`.

## Determinism

- Identical inputs + options ⇒ identical outputs.
- All data character-typed end to end; no implicit coercion.
- Sorting via `sort_pipeline_stage_dt()` for stable row order.
- Tests: no network/filesystem side effects; use `build_temp_dir()` + in-memory fixtures.

## Parallelism

Three stages parallelize via `future.apply::future_lapply()` when plan is non-sequential
and >1 work item: import read, import transform, list export.

**Import parallelism auto-enabled by default.** `resolve_import_effective_workers()`:
`"auto"` → `min(4, cores-1)` workers; explicit integer honored; `1` = sequential. Scoped
plan, restored on exit. ~4 workers is sweet spot (~2.1×); 8 < 4 in benchmarks.

## Output formats

- **Processed data → TSV** (`fwrite(sep="\t")`, only `harmonize` layer by default).
- **Unique lists → Excel** (`unique_*.xlsx`, one per column; identical layers merged).

## Gotchas

- Auto-run on source: disable `whep.run_*` options first if you only want definitions.
- `get_pipeline_constants()` caches globally with no invalidation — treat as immutable.
- `country` renamed to `polity` during import header normalization.
- Unit prefixes: leading numeric multiplier (e.g. `"1000 head"`) folded into value.
- Multi-pass cycle policy defaults to `"warn"`, max 10 passes, early convergence stop.

## Scratch files

Delete run logs (`*.out`), one-off scripts before committing. `.gitignore` covers
`perf/_*.R` and root `*.out`. Durable records go in `progress.md` / `results.tsv`.

## Maintaining these docs

- Reference files/function names, not line numbers.
- Update matching doc when changing a contract, entry point, constant, or option.
- Each doc has a distinct job — don't duplicate across them.
