# Constants & options

Two things are referenced from nearly every script: the constants list returned by
`get_pipeline_constants()`, and the `whep.*` global options. This is the reference for
both, so you don't have to re-read `01-constants.R` to recall a key.

**Authoritative source:** `r/0-general_pipeline/01-setup/01-constants.R`. If a value here
disagrees with that file, the file wins — update this doc.

## `get_pipeline_constants()`

Returns a cached named list (cached in `.pipeline_constants_cache` on first call; assumed
immutable — no invalidation). Access as `constants <- get_pipeline_constants()`. Keys by
category:

### Dataset, files, object names
- `dataset_default_name` = `"whep_data_raw"`.
- `files$raw_data` / `wide_raw_data` / `long_raw_data` = `"whep_data_raw.xlsx"`, `"whep_data_wide_raw.xlsx"`, `"whep_data_long_raw.xlsx"`.
- `object_names$*` — canonical environment object names: `raw`, `wide_raw`, `clean`, `normalize`, `harmonize` (`whep_data_*`), plus `export_paths`, `collected_reading_errors`, `collected_errors`, `collected_warnings`.

### Column groups & sorting
- `columns$base` = `c(continent, polity, unit, footnotes)` (required), `columns$id`, `columns$value` = `c(year, value)`, `columns$system` = `c(notes, yearbook, document)`.
- `sorting$stage_row_order` — the canonical column order: `hemisphere, continent, polity, commodity, variable, unit, year, value, notes, footnotes, yearbook, document`.

### NA / placeholder markers
- `na_placeholder` = `"..NA_INTERNAL.."`, `na_match_key` = `"..NA_MATCH_KEY.."`, `defaults$notes_value` = `NA_character_`.
- `defaults$unknown_document` = `"(unknown_document)"`, `unknown_commodity` = `"(unknown_commodity)"`, `list_blank_label` = `"(blank)"`, `unknown_filename` = `"unknown"`, `value_column` = `"value"`.

### Patterns (regex)
- Year column: `patterns$year_column` = `^\d{4}(-\d{4})?$`; 4-digit token = `^\d{4}$`.
- String/header normalization patterns (`normalize_non_alnum`, `header_normalize_*`, fast-path detectors).
- `patterns$footnote_non_alnum`, `file_extension`, `namespace_qualified` (`[A-Za-z][A-Za-z0-9.]*::`), `permission_error`.
- `header_normalization$canonical_aliases` = `c(country = "polity")`.

### Performance thresholds
- `performance$normalize_unique_min_n` = `256L`, `normalize_unique_sample_n` = `2048L`, `normalize_unique_ratio_threshold` = `0.85` (cardinality-aware string normalization).
- `performance$import_workbook_batch_size` = `32L`.
- `performance$import_parallel_workers` = `1L` (opt-in import parallelism; `1L` = sequential. Overridable by `config$performance$import_parallel_workers` or option `whep.import.parallel_workers`. See [conventions.md](conventions.md#parallelism)).

### Paths (relative names; absolute paths are built into `config$paths`)
- `paths$data_dir` = `"data"`; import: `import_dir`/`import_raw_dir`/`import_clean_dir`/`import_standardize_dir`/`import_harmonize_dir`; `postpro_dir` = `"2-postpro"`; export: `export_dir`/`export_lists_dir`/`export_processed_dir`; `checkpoints_dir` = `".checkpoints"`.

### Export config
- `export_config$data_suffix` = `".xlsx"` (legacy; processed data now writes **TSV** — see [conventions.md](conventions.md)), `list_suffix` = `"_unique.xlsx"`.
- `export_config$lists_to_export` — columns exported as unique lists (hemisphere…document, minus year/value).
- `export_config$export_layers` = `c("harmonize")` — **only the harmonize layer is exported by default**.
- `export_config$styles$error_highlight` — Excel cell style (orange fill, bold, thick border).

### Post-processing (`postpro$*`)
- Directory names: `audit_dir_name`, `diagnostics_dir_name`, `templates_dir_name`, `runtime_cache_dir_name`; audit/template file names.
- Rule matching: `rule_match_wildcard_token` = `"__ANY__"`; `rule_match_normalization` (`apply_once_before_stage = TRUE`, `apply_each_pass = FALSE`, `excluded_columns = c(year, value, yearbook, document)`).
- Target update: `target_update_strategies$default` = `"last_rule_wins"`; `concatenate_delimiter` = `"; "`; `by_column = c(notes = "concatenate")`; `supported = c(last_rule_wins, concatenate)`.
- Multi-pass: `multi_pass$enabled_by_stage = c(clean = TRUE, harmonize = TRUE)`, `max_passes_by_stage = c(clean = 10L, harmonize = 10L)`, `cycle_policy = "warn"` (or `"abort"`), `diagnostics_verbosity = "compact"`.
- Caches (both **disabled by default**): `runtime_cache$enabled = FALSE` (`max_entries = 128L`), `schema_validation_cache$enabled = FALSE` (`max_entries = 1024L`).

### Dependencies & load order
- `dependencies$required_packages` — the full package set (checkmate, cli, data.table, dplyr, fs, future, future.apply, here, openxlsx, progressr, purrr, readr, readxl, renv, stringi, stringr, tibble, tidyr, tidyselect, profvis, writexl).
- `script_names$pipeline_stage_runners` — the four stage-runner filenames, used by `resolve_pipeline_files()` in `run_pipeline.R`. **If you add or rename a stage runner, update this list.** This is the only entry in `script_names`; `run_general_pipeline()` discovers general-stage scripts dynamically by scanning `00-dependencies/`, `01-setup/`, `02-helpers/` and sourcing them alphabetically, so adding a helper does **not** require touching constants. See [conventions.md](conventions.md#adding-a-script).

### Misc
- `timestamp_format_utc` = `"%Y-%m-%dT%H:%M:%SZ"`; `transforms$latin_ascii_lower` = `"Latin-ASCII; Lower"`.
- `tokens$commodity_start_index` = `7L`; `general_pipeline$*` (progress bar width/messages, `total_steps = 5L`).

### Base R options set when `01-constants.R` loads
`stringsAsFactors = FALSE`, `scipen = 999`, `datatable.showProgress = FALSE`,
`datatable.verbose = FALSE`. (Side effect of sourcing the file.)

## `whep.*` option flags

All read via `getOption("whep.<name>", <default>)`. Names come from `constants$auto_run_options`,
`toggle_options`, and `options`.

| Option | Default | Controls |
|--------|---------|----------|
| `whep.run_pipeline.auto` | `TRUE` | Auto-run `run_pipeline()` when `r/run_pipeline.R` is sourced |
| `whep.run_general_pipeline.auto` | `TRUE` | Auto-run the general stage when its runner is sourced |
| `whep.run_import_pipeline.auto` | `TRUE` | Auto-run the import stage |
| `whep.run_postpro_pipeline.auto` | `TRUE` | Auto-run the post-processing stage |
| `whep.run_export_pipeline.auto` | `TRUE` | Auto-run the export stage |
| `whep.drop_na_values` | `TRUE` | `drop_na_value_rows()` removes rows with `NA` value |
| `whep.progress.enabled` | `TRUE` | `map_with_progress()` shows a `progressr` bar |
| `whep.checkpointing.enabled` | `FALSE` | Enable RDS checkpoint save/load for crash recovery |
| `whep.import.parallel_workers` | `1L` | Import worker count; `>1` runs import via `future::multisession` (`1` = sequential) |

> Tests set every `whep.run_*_pipeline.auto` and `whep.checkpointing.enabled` to `FALSE`
> (in `tests/test_helper.R`) so that sourcing pipeline files does not trigger a run.
> Apart from the import opt-in flag above (`whep.import.parallel_workers`, which
> `run_import_pipeline()` translates into a scoped `future::multisession` plan), parallelism
> is driven by the active `future::plan()` (see [conventions.md](conventions.md#parallelism)).
