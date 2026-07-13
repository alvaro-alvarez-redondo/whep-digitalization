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
- **Splitting a file — perf-harness caveat:** the runtime + tests load stages by
  glob, so a split file is auto-discovered there. But `perf/perf_pipeline/p9-orchestration.R`
  (read-only) loads a **hard-coded subset** of pipeline files by explicit path for its
  benchmarks, and `tests/perf/test-big-o-estimation.R` runs it (outside the autocode
  suite). If you split a file that p9 lists, the split-off functions won't be found there.
  Since p9 can't be edited, the original file must load its sibling with an
  `if (!exists(<fn>)) source(<sibling>)` guard (see `24-standardize-engine.R` →
  `24-standardize-aggregation.R`) — a no-op under the glob (the sibling sorts first),
  effective under p9's standalone source. p9 currently lists only the `24-standardize-*`
  and `21-*` postpro files, so only those need the guard.
- **New stage runner:** update `constants$script_names$pipeline_stage_runners`.

## Determinism

- Identical inputs + options ⇒ identical outputs.
- Character-typed through import; `value` is parsed to numeric at the post-processing
  audit step (`audit_data_output`), every other column stays character. No other
  implicit coercion.
- Sorting via `sort_pipeline_stage_dt()` for stable row order.
- Tests: no network/filesystem side effects; use `build_temp_dir()` + in-memory fixtures.

## Parallelism

Two sites parallelize via `future.apply::future_lapply()` when plan is non-sequential
and >1 work item: the fused import read+transform stage
(`read_transform_pipeline_files()`), and list export.

**Import parallelism auto-enabled by default.** `resolve_import_effective_workers()`:
`"auto"` → `min(import_parallel_workers_auto_max=8, cores-1)` workers; explicit integer
honored; `1` = sequential. Scoped plan, restored on exit. ~8 workers is the optimum on a
16-core box (~2.3×).

**Read and transform run fused, one unit of work per workbook batch** (jul4): each
batch worker reads its workbooks (`read_workbook_batch()`) and immediately transforms
each file (`transform_single_file()`), returning only transform results + read errors.
The two-stage arrangement returned all read data to the main process and re-exported it
to the transform workers — that re-export was the dominant main-process import cost
(~11.6s serialize of a ~69s import; fused A/B −14.5% with identical output).
`read_pipeline_files()` / `transform_files_list()` remain as unit-tested building
blocks, not the runtime path.

The fused `future_lapply` passes `future.scheduling =
resolve_import_future_scheduling(config)` (constant `4`) so it makes more, smaller chunks.
This matters for **progress**: `progressr` only relays a worker's progress when its future
**resolves**, and the default factor of 1 makes few chunks → the bar can sit still then jump.
Scheduling is safe here because the fused closure captures only small `config` + the batch's
own metadata rows. (Historical: scheduling was **never** safe for the old two-stage
transform, whose closure captured the large `read_data_list` — more chunks re-serialized it,
measured ~5x slower; `future_mapply`-over-data was even worse.) The progressor ticks read and
transform once per file inside both the sequential and parallel branches, so the import
budget (`2*nfiles + 4`) closes identically in either mode; read/transform ticks interleave
per batch instead of arriving as two separate sweeps.

## Progress bars

Colors are theme-aware: `pipeline_progress_dark()` (the `whep.progress.dark` option, else the
RStudio editor theme, else **default dark**) picks `constants$progress$palette$light` vs
`$dark`. Fixed ANSI shades like `col_silver` (`\e[90m`) read fine on light backgrounds but
muddy on dark, so dark mode uses white + soft pastel truecolor (`col_br_white`,
`make_ansi_style('#a6c8ff')`, `make_ansi_style('#a6e3a1')`). Set
`options(whep.progress.dark = FALSE)` for light.

All four stage runners wrap their work in `with_pipeline_progress(expr, stage)` (not
`progressr::with_progress()` directly), which bundles the handler, gate, redraw throttle, and
output buffering. The handler (`pipeline_progress_handlers(stage)`) is one visual family
(spinner + bar + percent + live status, no ETA), distinguished by a stage label baked into the
cli format string (not `{cli::pb_name}`, which is always empty because `progressor()` has no
`name=`). Rendering is gated by `pipeline_progress_enabled()` = `whep.progress.enabled` **and**
`interactive()`, so tests/benchmark/batch runs stay silent.

**Anti-flicker:** the import bar relays progress in bursts as parallel futures resolve. Two
settings keep it from vanishing/reappearing: a redraw throttle (`constants$progress$update_interval`,
passed to the handler so a burst repaints once) and `delay_stdout`/`delay_conditions`/`delay_terminal`
in `with_pipeline_progress` (buffer relayed worker output so progressr never clears the bar
mid-run to flush it). cli self-throttles renders, so the throttle alone isn't enough — the
buffering is what stops the per-future clear/redraw.

The orchestrator's own console lines (`run_pipeline.R`: "running pipeline script: …" and
"Pipeline completed …") use `pipeline_alert_info()` / `pipeline_alert_success()` instead of
`cli::cli_alert_*`, so their symbols/accents match the bar palette (the success tick is the
same pastel green as the bars'). `run_pipeline.R` sources `02-progress.R` in its bootstrap
guard so those helpers exist before the first message. Errors/warnings still use cli's default
(red/yellow) — only the info/success lines are repainted. The long postpro multi-pass clean/harmonize loop calls a `progress_pulse`
callback (`progress(msg, amount = 0)`) per pass to animate without advancing the 9 fixed ticks.
Don't add `format_failed` — progressr doesn't render it on a thrown condition; abort at the
call site instead. All format strings / labels / messages live in `constants$progress`.

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
