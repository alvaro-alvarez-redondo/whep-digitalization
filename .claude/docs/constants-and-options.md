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
- `performance$import_parallel_workers` = `"auto"` (→ `min(import_parallel_workers_auto_max, cores-1)` workers; explicit int honored; `1L` = sequential). `import_parallel_workers_auto_max` = `8L`.
- `performance$import_future_scheduling` = `4` — `future_lapply` scheduling factor for the parallel import **read** stage only (`~factor * workers` chunks). Higher = more, smaller chunks → progress relays steadily instead of in one end-of-stage burst. Perf-neutral there (read closure captures only small `config`). NOT applied to transform (its closure captures the large `read_data_list`; more chunks measured ~5x slower). Override via `config$performance$import_future_scheduling`.

### Progress presentation (`progress$*`)
Shared cli-backed progress-bar config used by all four stage runners via
`pipeline_progress_handlers(stage)` (in `02-progress.R`), which **assembles the
cli format string at build time** from these pieces (the colors are theme-aware,
so finished format strings can't be precomputed). One visual family (spinner +
bar + percent + live status; no ETA); stages differ only by a label baked in as a
literal — `progressr::progressor()` has no `name=`, so `{cli::pb_name}` can't be
used. Keys: `stage_labels` (`general/import/postpro/export`); `rate_stages` =
`"import"` (the only stage whose line adds `{cli::pb_rate}`); `palette$light`
/`palette$dark` — a cli call per role (`muted`/`accent`/`success`) spliced as
`{cli::<value>(<token>)}`, chosen by `pipeline_progress_dark()`. Dark mode uses
white + soft pastel truecolor (`col_br_white`, `make_ansi_style('#a6c8ff')`,
`make_ansi_style('#a6e3a1')`) so text stays legible and calm on a dark console;
`update_interval` (`0.2` — minimum seconds between bar redraws, so the bursty
parallel-import relay repaints once per burst instead of flickering); `show_after`;
`fallback_bar_width`
(txtProgressBar fallback); `pulse_template` (`"%s pass %d"`, the postpro per-pass
`amount = 0` pulse); per-step `messages$import/postpro/export`. No
`format_failed` — progressr does not render a custom failure format on a thrown
condition.

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
| `whep.progress.enabled` | `TRUE` | Show the cli progress bar. Effective only when **also** `interactive()` — non-interactive runs (tests, benchmark, batch) stay silent. Gated via `pipeline_progress_enabled()`. |
| `whep.progress.dark` | not set | Force the dark (`TRUE`) or light (`FALSE`) bar palette. Unset → respect `rstudioapi::getThemeInfo()$dark` if RStudio reports it, **else default dark**. Resolved by `pipeline_progress_dark()`. |
| `whep.checkpointing.enabled` | `FALSE` | Enable RDS checkpoints |
| `whep.import.parallel_workers` | not set | Import worker count override (`"auto"` default from constant) |

Tests set all `whep.run_*` and `whep.checkpointing.enabled` to `FALSE`.
