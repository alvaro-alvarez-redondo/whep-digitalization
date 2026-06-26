# Codebase map

Where every function lives, by stage and file. Use this as a lookup index instead of
grepping the tree. **PUB** = called across stages / by the orchestrator / by tests;
**int** = internal helper. Signatures are abbreviated; open the file for exact args.

For the architecture and data flow, see [architecture.md](architecture.md). For the
constants and option flags these functions read, see
[constants-and-options.md](constants-and-options.md).

> 62 source `.R` files + 34 test files. This index lists durable function names and
> responsibilities; it intentionally omits line numbers (they rot). Re-derive a stale
> entry by reading the named file.

---

## Stage 0 — general pipeline (`r/0-general_pipeline/`)

### `00-dependencies/`
| Function | File | Purpose | |
|---|---|---|---|
| `check_dependencies(packages)` | `00-install.R` | Identify missing packages, install via `renv` | PUB |
| `load_dependencies(packages)` | `00-load.R` | Attach packages, suppress startup messages | PUB |
| `abort_on_checkmate_failure(check_result)` | `00-validation.R` | Turn checkmate failures into CLI aborts | int |
| `collect_namespaced_dependencies(scripts_root)` / `audit_dependency_registry(...)` | `00-audit.R` | Scan `pkg::fn` usage; compare declared vs used | int |

### `01-setup/`
| Function | File | Purpose | |
|---|---|---|---|
| `get_pipeline_constants()` | `01-constants.R` | Cached named list of **all** constants. Most-called function in the repo. | PUB |
| `load_pipeline_config(dataset_name, ...)` | `01-config.R` | Build the `config` object (paths, columns, export, postpro settings) | PUB |
| `create_required_directories(paths)` | `01-directories.R` | Create import/export dirs **and the audit subtree** (contract) | PUB |
| `resolve_audit_root_dir` / `ensure_directories_exist` / `delete_directory_if_exists` / `ensure_output_directories` | `01-directories.R` | Directory helpers | int |

### `02-helpers/` (sourced alphabetically; all loaded before any stage runs)
| Function | File | Purpose | |
|---|---|---|---|
| `assert_or_abort(check_result)` | `02-assertions.R` | Pass `TRUE`, abort on error string — used by every helper | int |
| `save/load/clear_pipeline_checkpoint(...)` | `02-checkpoints.R` | RDS checkpointing (gated by `whep.checkpointing.enabled`) | PUB |
| `get_config_string` / `generate_export_path(config, base, type, ...)` | `02-config-accessors.R` | Nested config access; build export paths. `generate_export_path` is dead code (superseded by `build_processed_export_path()`; remove) | PUB/dead |
| `drop_na_value_rows(dt, value_column)` | `02-data-cleaning.R` | Drop NA-value rows (gated by `whep.drop_na_values`) | PUB |
| `ensure_data_table` / `copy_as_data_table` / `coerce_to_data_table` | `02-data-table.R` | data.frame ↔ data.table coercion | int |
| `assign_environment_values(values, env)` | `02-environment.R` | Deterministic named assignment into an env | int |
| `validate_export_import(df, base_name)` | `02-export-validation.R` | Validate export input is a non-empty data.frame | int |
| `cached_unzip(zip_path, exdir, overwrite)` | `02-io-cache.R` | Unzip only when archive newer than target | PUB |
| `coerce_numeric_safe(x)` | `02-numeric-coercion.R` | Char→numeric, empties/non-numeric → NA, no warnings | PUB |
| `map_with_progress(x, .f, ...)` | `02-progress.R` | `progressr`-aware map (gated by `whep.progress.enabled`) | PUB |
| `sort_pipeline_stage_dt(dt, sort_columns)` | `02-sorting.R` | Sort by canonical business-key order | PUB |
| `normalize_string` / `normalize_string_impl` / `clean_footnote` / `normalize_filename` | `02-string-normalization.R` | Lowercase-ASCII normalization (cardinality-aware fast path) | PUB/int |
| `format_elapsed_time(seconds)` | `02-time-formatting.R` | Format `Ns` / `Nm Ns` / `Nh Nm` for CLI | PUB |
| `extract_yearbook(parts)` / `extract_commodity(parts)` | `02-token-extraction.R` | Parse tokens out of filenames | int |

### Orchestrators
| Function | File | Purpose | |
|---|---|---|---|
| `run_general_pipeline(dataset_name)` | `run_general_pipeline.R` | Source scripts → check/load deps → build config → create dirs → return `config` | PUB |
| `run_pipeline(show_view, pipeline_root)` | `r/run_pipeline.R` | Run the 4 stages in order; report elapsed time + pass counts | PUB |
| `build_postpro_iteration_summary` / `get_postpro_iteration_loop_counts` / `resolve_pipeline_files` / `run_pipeline_script` / `maybe_view_pipeline_output` / `assert_pipeline_runtime_dependencies` | `r/run_pipeline.R` | Orchestration helpers | int |

---

## Stage 1 — import (`r/1-import_pipeline/`)

### `10-file_io/`
| Function | File | Purpose | |
|---|---|---|---|
| `discover_files(import_folder)` | `10-discovery.R` | Recursively find `.xlsx`; extract file metadata → `data.table` | PUB |
| `build_empty_file_metadata()` / `extract_file_metadata(file_paths)` | `10-metadata.R` | Empty metadata schema; parse yearbook/commodity from names | int |

### `11-reading/`
| Function | File | Purpose | |
|---|---|---|---|
| `read_pipeline_files(file_list_dt, config, progressor)` | `11-batching.R` | Batch + read files (parallel when a non-sequential `future` plan is set) | PUB |
| `split_workbook_batches` / `resolve_import_workbook_batch_size` / `read_workbook_batch` | `11-batching.R` | Batching internals | int |
| `normalize_header_names` / `validate_header_normalization` / `resolve_canonical_header_renames` | `11-header-normalization.R` | Normalize + canonicalize headers (alias `country → polity`) | int |
| `read_excel_sheet` / `read_file_sheets` / `compute_non_empty_base_rows` | `11-sheet-read.R` | Read a sheet/file as text; tag `variable := sheet_name`; drop empty rows | int |
| `assert_read_result_contract` / `build_read_error` / `safe_execute_read` / `has_read_errors` / `normalize_pipeline_read_result` / `create_empty_read_result` | `11-read-utils.R` | Read-result shape + error aggregation | int |

### `12-transform/`
| Function | File | Purpose | |
|---|---|---|---|
| `transform_files_list(file_list_dt, read_data_list, config, progressor)` | `12-processing.R` | Transform all files → consolidated `list(wide_raw, long_raw)` | PUB |
| `process_files` / `transform_single_file` | `12-processing.R` | Per-file transform (parallel when plan is non-sequential) | int |
| `assert_transform_result_contract(transform_result)` | `12-reshape.R` | **Contract:** result is `list(wide_raw, long_raw)`, both data.table | int |
| `reshape_to_long` / `add_metadata` / `transform_file_dt` / `resolve_commodity_name` / `build_empty_transform_result` | `12-reshape.R` | Wide→long melt; attach document/notes/yearbook | int |
| `identify_year_columns` / `normalize_key_fields` / `convert_year_columns` | `12-transform-utils.R` | Detect year columns (`^\d{4}(-\d{4})?$`); normalize keys; clean year names | int |

### `13-output/`
| Function | File | Purpose | |
|---|---|---|---|
| `consolidate_audited_dt(dt_list, config)` | `13-output.R` | Row-bind with fill; enforce canonical column order | PUB |
| `validate_output_column_order(config)` | `13-output.R` | Verify configured order covers the target schema | int |
| `validate_long_dt(long_dt, config)` | `13-validate.R` | Run mandatory-field, year, duplicate validators; collect errors (non-fatal) | PUB |
| `validate_mandatory_fields_dt` / `detect_duplicates_dt` / `validate_year_values` | `13-validate.R` | Individual validators | int |

### Orchestrator: `run_import_pipeline(config)` → `list(data, wide_raw, diagnostics)`; plus `run_import_pipeline_auto(auto_run, env)`.

---

## Stage 2 — post-processing (`r/2-postpro_pipeline/`)

Largest stage. `source_postpro_scripts()` runs at module load (sourcing
`run_postpro_pipeline.R` loads the whole stage). See [conventions.md](conventions.md).

### `20-data_audit/`
| Function | Purpose | |
|---|---|---|
| `audit_data_output(dataset_dt, config)` | Run all validations on raw input → findings | PUB |
| `audit_character_non_empty` / `audit_numeric_string` / `run_master_validation` / `build_audit_validation_plan` / `resolve_audit_columns_by_type` / `export_validation_audit_report` / `load_audit_config` / `resolve_audit_output_paths` / `prepare_audit_root` / `empty_audit_findings_dt` | Validation strategy, findings export | int |

### `21-postpro_utilities/`
| Function | Purpose | |
|---|---|---|
| `initialize_postpro_output_root(config)` | Ensure audit/diagnostics/templates/cache dirs exist | PUB |
| `generate_postpro_rule_templates(config, overwrite)` | Write rule template workbooks | PUB |
| `load_stage_rule_payloads(config, stage_name)` | Load all rule files for a stage (`clean`/`harmonize`) | PUB |
| `get_cached_stage_payload_bundle(config, stage_name)` | Resolve rule bundle via 2-level (memory + disk) cache | PUB |
| `build_layer_diagnostics` / `get_postpro_output_paths` / `get_canonical_rule_columns` / `validate_postpro_stage_name` | Diagnostics + helpers | int |

### `22-clean_harmonize_data/` (multi-pass rule loop)
| Function | Purpose | |
|---|---|---|
| `run_cleaning_layer_batch(dataset_dt, config, dataset_name)` | Run the **clean** stage (multi-pass) | PUB |
| `run_harmonize_layer_batch(dataset_dt, config, dataset_name)` | Run the **harmonize** stage (multi-pass) | PUB |
| `run_rule_stage_layer_batch(dataset_dt, config, stage_name, dataset_name)` | Shared multi-pass driver for both | PUB |
| `resolve_stage_multi_pass_controls` / `canonicalize_post_loop_annotation_columns` / `drop_empty_footnotes_column` | Multi-pass internals | int |

### `23-postpro_rule_engine/` (matching + application)

Rule files (clean/harmonize workbooks/CSVs) use six canonical columns from
`get_canonical_rule_columns()` (`21-postpro_utilities/21-stage-definitions.R`):
`column_source`, `value_source_raw`, `value_source`, `column_target`, `value_target_raw`,
`value_target`.

| Function | Purpose | |
|---|---|---|
| `validate_canonical_rules(rules_dt, dataset_dt, ...)` | Validate a rule file against the dataset | PUB |
| `apply_rule_payload(dataset_dt, canonical_rules, stage_name, ...)` | Apply one rule file (matching + target updates) | PUB |
| `coerce_rule_schema` / `encode_rule_match_key` / `match_rule_target_condition_values` / `apply_target_updates_with_strategy` / `build_conditional_rule_dictionary` / `apply_footnote_rules` | Wildcard `__ANY__`, match-key normalization, `last_rule_wins`/`concatenate` strategies | int |

### `24-standardize_units/` (unit conversion)
| Function | Purpose | |
|---|---|---|
| `apply_standardize_rules(mapped_dt, prepared_rules_dt, unit_column, value_column, commodity_column)` | **Contract:** returns `list(data, matched_count, unmatched_count, matched_rule_counts)` — `matched_rule_counts` is a `data.table` | PUB |
| `run_standardize_units_layer_batch(clean_dt, config, unit_column, value_column, commodity_column, aggregate_after_standardize)` | Orchestrate standardization (+ optional row aggregation) | PUB |
| `load_units_standardization_rules(config)` / `prepare_standardize_rules(raw_rules_dt)` | Load + prepare unit rules | PUB |
| `aggregate_standardized_rows` / `extract_aggregated_rows` / `attach_standardize_diagnostics` / `build_standardize_layer_audit` | Aggregation + audit | int |

### `25-postpro_diagnostics/`
| Function | Purpose | |
|---|---|---|
| `assert_postpro_preflight(preflight_result)` | Abort if preflight checks failed | PUB |
| `persist_postpro_audit(clean_audit_dt, harmonize_audit_dt, standardize_audit_dt, ...)` | Write audit workbooks | PUB |
| `collect_postpro_preflight` / `build_postpro_diagnostics` / `summarize_stage_rules` / `build_unmatched_rule_summary` | Preflight + summaries | int |

### Orchestrator
| Function | Purpose | |
|---|---|---|
| `run_postpro_pipeline_batch(raw_dt, config, dataset_name = ...)` | 9-step: audit → init → templates → preflight → **clean → standardize → harmonize** → diagnostics → persist audit. Returns harmonized dt with `pipeline_diagnostics` attr | PUB |
| `source_postpro_scripts(pipeline_root)` | Source all postpro scripts in deterministic order (runs at module load) | PUB |
| `run_postpro_pipeline_auto(auto_run, env)` | Auto-run wrapper | int |

---

## Stage 3 — export (`r/3-export_pipeline/`)

### `30-processed_data/` (writes **TSV**)
| Function | File | Purpose | |
|---|---|---|---|
| `export_processed_data(config, data_objects, overwrite, env)` | `04-export-processed-data.R` | Export only layers in `export_config$export_layers` (default `harmonize`) as TSV | int |
| `collect_layer_tables_for_export(data_objects, env, layer_suffixes)` | `02-collect-layer-tables.R` | Detect `_raw/_clean/_normalize/_harmonize` objects; exclude `_wide_raw`/`_post_processed` | int |
| `build_processed_export_path(config, object_name)` | `01-build-processed-export-path.R` | `{normalized_name}.tsv` under `export/processed` | int |
| `write_processed_table_fast(data_dt, output_path, overwrite)` | `03-write-processed-table-fast.R` | `data.table::fwrite(sep = "\t")` | int |

### `31-lists/` (writes **xlsx** `unique_*.xlsx`)
| Function | File | Purpose | |
|---|---|---|---|
| `export_lists(config, data_objects, overwrite, env)` | `04-cache-and-write.R` | One workbook per column; parallel when plan non-sequential & >1 column | int |
| `write_column_lists_workbook` / `build_column_unique_cache` | `04-cache-and-write.R` | Per-column workbook write (`writexl::write_xlsx`); precompute unique values | int |
| `build_column_lists_export_path` / `compute_unique_column_values` / `build_layer_tables_by_sheet` / `collect_union_columns` | `02-build-path-and-unique-values.R` | Path, unique values, per-sheet layer tables | int |
| `resolve_lists_export_columns` / `normalize_for_comparison` / `are_list_tables_identical` / `resolve_list_sheet_payloads` | `03-resolve-and-compare.R` | Resolve columns; merge identical layers into one sheet (e.g. `raw_clean_...`) | int |
| `get_lists_sheet_order` / `infer_layer_sheet_name` | `01-sheet-order-and-infer.R` | Fixed sheet order raw→clean→normalize→harmonize | int |

### Orchestrator
| Function | Purpose | |
|---|---|---|
| `run_export_pipeline(config, data_objects = NULL, overwrite = TRUE, env = .GlobalEnv)` | Source export scripts → collect layers → create dirs → `export_processed_data` + `export_lists` → assert contract. Returns `list(processed_paths, lists_paths)` | PUB |
| `assert_export_paths_contract(export_result)` | **Contract:** `list(processed_paths, lists_paths)`, both non-empty named char vectors | int |
| `run_export_pipeline_auto(auto_run, env)` | Auto-run wrapper | PUB |
