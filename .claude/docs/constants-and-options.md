# Constants & options

**Authoritative source:** `r/0-general_pipeline/01-setup/01-constants.R`.

## `get_pipeline_constants()`

Cached named list (`.pipeline_constants_cache`, no invalidation). Access: `constants <- get_pipeline_constants()`.

### Dataset, files, object names
- `dataset_default_name` = `"whep_data_raw"`.
- `files$raw_data`/`wide_raw_data`/`long_raw_data` = `"whep_data_raw.xlsx"` etc.
- `object_names$*` — canonical env names: `raw`, `wide_raw`, `clean`, `normalize`, `harmonize` (`whep_data_*`), plus `export_paths`, `collected_reading_errors`, etc.

### Column groups & sorting
- `columns$base` = `c(continent, polity, unit, footnotes)`, `$id`, `$value` = `c(year, value)`, `$system` = `c(notes, yearbook, document)`.
- `sorting$stage_row_order` — canonical order: `hemisphere, continent, polity, commodity, variable, unit, year, value, notes, footnotes, yearbook, document`.

### NA / placeholder markers
- `na_placeholder` = `"..NA_INTERNAL.."`, `na_match_key` = `"..NA_MATCH_KEY.."`.
- `defaults$unknown_document` = `"(unknown_document)"`, `unknown_commodity` = `"(unknown_commodity)"`, `list_blank_label` = `"(blank)"`.

### Performance thresholds
- `performance$normalize_unique_min_n` = `256L`, `sample_n` = `2048L`, `ratio_threshold` = `0.85`.
- `performance$import_workbook_batch_size` = `32L`.
- `performance$import_parallel_workers` = `"auto"` (→ `min(4, cores-1)` workers; explicit int honored; `1L` = sequential).

### Paths
- Relative names under `data/`: `import_dir`, `import_raw_dir`, `import_clean_dir`, `import_standardize_dir`, `import_harmonize_dir`, `postpro_dir`, `export_dir`, etc.

### Export config
- `export_config$lists_to_export` — columns exported as unique lists.
- `export_config$export_layers` = `c("harmonize")`.
- `export_config$data_suffix` = `".xlsx"` — **dead code** (processed export uses `.tsv`; remove per no-scaffolding standard).

### Post-processing (`postpro$*`)
- `rule_match_wildcard_token` = `"__ANY__"`.
- `rule_match_normalization$excluded_columns` = `c(year, value, yearbook, document)`.
- `target_update_strategies$default` = `"last_rule_wins"`; `by_column = c(notes = "concatenate")`.
- `multi_pass$max_passes_by_stage` = `c(clean = 10L, harmonize = 10L)`, `cycle_policy = "warn"`.
- `runtime_cache$enabled = FALSE`, `schema_validation_cache$enabled = FALSE`.

### Dependencies
- `dependencies$required_packages` — checkmate, cli, data.table, dplyr, fs, future, future.apply, here, openxlsx, progressr, purrr, readr, readxl, renv, stringi, stringr, tibble, tidyr, tidyselect, profvis, writexl.
- `script_names$pipeline_stage_runners` — the four stage-runner filenames (update if adding/renaming a stage runner).

### Base R options set on load
`stringsAsFactors = FALSE`, `scipen = 999`, `datatable.showProgress = FALSE`, `datatable.verbose = FALSE`.

## `whep.*` option flags

| Option | Default | Controls |
|--------|---------|----------|
| `whep.run_pipeline.auto` | `TRUE` | Auto-run on source |
| `whep.run_general_pipeline.auto` | `TRUE` | Auto-run general stage |
| `whep.run_import_pipeline.auto` | `TRUE` | Auto-run import stage |
| `whep.run_postpro_pipeline.auto` | `TRUE` | Auto-run postpro stage |
| `whep.run_export_pipeline.auto` | `TRUE` | Auto-run export stage |
| `whep.drop_na_values` | `TRUE` | Drop rows with NA value |
| `whep.progress.enabled` | `TRUE` | Show progressr bar |
| `whep.checkpointing.enabled` | `FALSE` | Enable RDS checkpoints |
| `whep.import.parallel_workers` | not set | Import worker count override (`"auto"` default from constant) |

Tests set all `whep.run_*` and `whep.checkpointing.enabled` to `FALSE`.
