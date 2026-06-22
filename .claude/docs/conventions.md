# Conventions & gotchas

Operational knowledge: how to run and test the pipeline, how loading works, what's
deterministic, and the non-obvious behaviors that bite. Pair this with
[architecture.md](architecture.md) (mental model), [codebase-map.md](codebase-map.md)
(function index), and [constants-and-options.md](constants-and-options.md) (config surface).

## Running the pipeline

```r
source(here::here("r", "run_pipeline.R"), local = TRUE)
run_pipeline(show_view = FALSE, pipeline_root = here::here("r"))
```

Sourcing `run_pipeline.R` **auto-runs** the whole pipeline unless `whep.run_pipeline.auto`
is `FALSE`. The same auto-run pattern applies to each stage runner. To source without
running, set the relevant `whep.run_*_pipeline.auto` options to `FALSE` first.

## Running tests

The full suite spans five directories. The working, canonical way to run them all is the
command in `autocode.toml` (`[metrics.tests]`), which sources `tests/test_helper.R` and
runs each of:

```
tests/0-general_pipeline/  tests/1-import_pipeline/  tests/2-post_processing_pipeline/
tests/3-export_pipeline/   tests/testthat/scripts/
```

`tests/test_helper.R` is the shared harness: it disables all auto-run options and
checkpointing, sources the general-stage scripts and helpers, and defines in-memory
fixtures (`build_temp_dir`, `build_test_config`, `create_test_xlsx`, `build_sample_long_dt`).
Per-stage test files source the stage they exercise (e.g. post-processing tests source
`r/2-postpro_pipeline/run_postpro_pipeline.R`, which loads the whole stage).

> ⚠️ **`tests/testthat/test_all.R` is currently broken** — it sources
> `tests/testthat/r/test_setup_context.R` and runs `test_dir("tests/testthat/r")`, but the
> `tests/testthat/r/` directory does not exist (the contract tests live in
> `tests/testthat/scripts/`). The README's "run all tests" snippet points at the same dead
> path. Use the `autocode.toml` command instead until `test_all.R` is fixed.

### `tests/testthat/scripts/` vs the per-stage suites

`scripts/` holds **contract tests** that re-assert critical API shapes independently of
`test_helper.R` (they source their own dependencies via `test_setup_context.R`). They run
*in addition to* — not instead of — the per-stage suites, and act as insurance against
refactors silently changing a contract. Historically two of them contradicted the main
suites; exp-18 aligned the stale ones to the authoritative behavior recorded in
[architecture.md](architecture.md) and `progress.md`. Keep both in sync.

## Loading & source order

- There is **no R package** — everything is `source()`d. Order matters.
- `01-constants.R` must load before anything else: `get_pipeline_constants()` underpins
  config, helpers, and every stage. Then config → directories → helpers (sourced
  alphabetically within `02-helpers/`).
- **`source_postpro_scripts()` runs at module load** (bottom of
  `r/2-postpro_pipeline/run_postpro_pipeline.R`). So sourcing that one file loads the
  entire post-processing stage — tests and callers do not need to source submodules
  individually. (An earlier state only sourced them inside the batch function, which broke
  direct-call tests; that is fixed.)

### Adding a script

- **General-stage script** (a new file under `00-dependencies/`, `01-setup/`, or
  `02-helpers/`): just drop it in with the right `0X-` prefix. `run_general_pipeline()`
  scans each directory and sources files **alphabetically**, so the prefix controls order.
  No constants change is needed — script discovery is dynamic (see
  [constants-and-options.md](constants-and-options.md)).
- **Stage-1/2/3 module**: each stage runner iterates a **hardcoded list of subdirectories**
  and within each one sources files **alphabetically**. So a new file in an *existing*
  subdir is picked up automatically (its `NX-` prefix sets the order). But a new
  *subdirectory* must be added to that runner's subdir vector — `import_stage_dirs`
  (`run_import_pipeline.R`), `stage_dirs` (`source_postpro_scripts` in
  `run_postpro_pipeline.R`), or `export_stage_dirs` (`run_export_pipeline.R`). Note the
  post-processing subdir order is deliberately **not** numeric — it sources
  `20, 21, 23, 22, 24, 25` (rule engine `23` loads before clean/harmonize `22`).
- **A whole new stage runner** (or renaming an existing one): update
  `constants$script_names$pipeline_stage_runners`, which `resolve_pipeline_files()` in
  `r/run_pipeline.R` uses to order the four stages. This is the one script list that is
  actually constant-driven.

## Determinism (a hard requirement)

- Identical inputs + options ⇒ identical outputs. Stage order is fixed by the orchestrator.
- Data is **character-typed end to end** (Excel read with `col_types = "text"`); `year` and
  `value` stay strings; no implicit date/number coercion.
- Sorting uses `sort_pipeline_stage_dt()` (canonical key order) so output row order is stable.
- Tests must avoid network and real-filesystem side effects — use `build_temp_dir()` and
  in-memory fixtures; seed any randomness. No committed fixture files.

## Parallelism

Three stages parallelize via `future.apply::future_lapply()` **only when** the active
`future::plan()` is non-sequential *and* there is more than one work item:

- Import read — `read_pipeline_files()` (batch size `performance$import_workbook_batch_size`, default 32).
- Import transform — `process_files()` (per file).
- List export — `export_lists()` (per column).

The default `future::sequential` keeps everything serial and deterministic. Output is
**identical** under a parallel plan (`future.apply` preserves input order; results are not
seed-dependent) — verified on the full dataset.

**Import has an opt-in flag.** `run_import_pipeline()` resolves a worker count via
`resolve_import_parallel_workers()` (option `whep.import.parallel_workers` ▸
`config$performance$import_parallel_workers` ▸ constant default `1L`). When `> 1`, it sets
`future::plan(future::multisession, workers = N)` **for that call only** and restores the
caller's plan on exit — the global-state change stays scoped to the entry point. Default is
`1L` (sequential). Import is I/O + serialization bound, so ~4 workers is the sweet spot
(~2.3× on the full dataset); more workers can be *slower* (8 < 4 in benchmarks). To
parallelize the other two stages, set a non-sequential plan yourself before calling them.

## Output formats (note the split)

- **Processed data → TSV.** `30-processed_data` writes `{name}.tsv` via
  `data.table::fwrite(sep = "\t")` (migrated from `.xlsx` in exp-17). Only the `harmonize`
  layer is exported by default (`export_config$export_layers`).
- **Unique lists → Excel.** `31-lists` writes `unique_{column}.xlsx` via
  `writexl::write_xlsx()`, one workbook per column. Identical layers are merged into a
  single sheet whose name concatenates the layers (e.g. `raw_clean_normalize_harmonize`);
  the `year` column is dropped before the layer-equality comparison.

## Other gotchas

- **Auto-run on source.** Because sourcing a stage runner can execute it, be deliberate
  when sourcing pipeline files in an interactive session — disable the auto-run options
  first if you only want the function definitions.
- **`get_pipeline_constants()` caches and mutates global state** (`.pipeline_constants_cache`),
  with no invalidation. Treat constants as immutable within a session.
- **Checkpoints are uncompressed** (`compress = FALSE`) for speed; they live under
  `data/.checkpoints/` and are gated by `whep.checkpointing.enabled`.
- **Header alias:** `country` is renamed to `polity` during import header normalization.
- **Unit prefixes:** the standardize engine extracts a leading numeric multiplier from a
  unit string (e.g. `"1000 head"`) and folds it into the value.
- **Multi-pass cycle policy** defaults to `"warn"` (continues) rather than `"abort"`;
  clean and harmonize each run up to 10 passes and stop early on convergence.

## Maintaining these docs

These docs exist so a session can understand the repo by reading rather than rescanning.
Keep them durable:

- Reference **files and function names**, not line numbers (line numbers rot fastest).
- When you change a contract, an entry point signature, a constant, or an option, update
  the matching doc in the same change — and `progress.md` if it records a milestone.
- The four `docs/` files have distinct jobs: mental model (architecture), where-things-live
  (codebase-map), config surface (constants-and-options), how-to + gotchas (conventions).
  Put new knowledge in the one that fits; don't duplicate across them.
