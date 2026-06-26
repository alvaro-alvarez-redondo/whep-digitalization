# Architecture

## Overview

A deterministic, script-oriented R pipeline. `r/run_pipeline.R` orchestrates four stages
in fixed order, sourcing each stage runner in turn:

```
general bootstrap  →  import  →  post-processing  →  export
   (stage 0)         (stage 1)     (stage 2)         (stage 3)
```

Each stage lives in a numbered directory under `r/`; scripts carry numeric prefixes that
encode source/execution order. There is **no package** — code is sourced, not installed.

## Stage layout

| Stage | Directory | Responsibility |
|-------|-----------|----------------|
| 0 — General | `r/0-general_pipeline/` | Dependency checks, config + directory construction, shared helpers |
| 1 — Import | `r/1-import_pipeline/` | File discovery, read, transform (wide→long), validation |
| 2 — Post-processing | `r/2-postpro_pipeline/` | Audit, clean, standardize units, harmonize, diagnostics |
| 3 — Export | `r/3-export_pipeline/` | Processed-data TSVs and unique-list workbooks |

Stage 0 sub-structure (the parts most code touches):
- `01-setup/01-constants.R` — **all** centralized constants; reached via `get_pipeline_constants()`.
- `01-setup/01-config.R` — builds the `config` object. `01-directories.R` — creates the directory tree.
- `02-helpers/` — string normalization, numeric coercion, data.table utils, sorting, checkpoints, etc.

## Data flow

Each stage hands a `data.table` (plus diagnostics) to the next. Stage objects are assigned
in the environment under canonical names (`whep_data_raw`, `whep_data_clean`,
`whep_data_normalize`, `whep_data_harmonize`).

```
Excel workbooks (data/1-import/10-raw_import/**.xlsx)
   │  discover_files → read_pipeline_files → transform_files_list → validate_long_dt
   ▼
IMPORT result: list(data = long dt, wide_raw = wide dt, diagnostics)
   │  run_postpro_pipeline_batch:  audit → CLEAN → STANDARDIZE UNITS → HARMONIZE → persist audit
   ▼
POSTPRO result: harmonized data.table  (attr: pipeline_diagnostics{clean, harmonize, ...})
   │  run_export_pipeline:  export_processed_data (TSV) + export_lists (xlsx)
   ▼
EXPORT result: list(processed_paths, lists_paths)
```

### Canonical column order

```
hemisphere, continent, polity, commodity, variable, unit, year, value,
notes, footnotes, yearbook, document
```

All pipeline data is **character-typed** end to end. Rows with `value = NA` are dropped by
default (`whep.drop_na_values`).

## Entry points

- `run_pipeline(show_view, pipeline_root)` — top-level orchestrator.
- `run_general_pipeline(dataset_name)` → returns `config`.
- `run_import_pipeline(config)` → `list(data, wide_raw, diagnostics)`.
- `run_postpro_pipeline_batch(raw_dt, config, dataset_name)` → harmonized `data.table` with `pipeline_diagnostics` attribute. **Three args** — unit/value/commodity column names are parameters of `run_standardize_units_layer_batch`, not the batch orchestrator.
- `run_export_pipeline(config, data_objects, overwrite, env)` → `list(processed_paths, lists_paths)`.

Auto-run wrappers fire when `whep.run_*_pipeline.auto` is `TRUE` (default). Tests disable them.

## Contracts — do not break without updating tests

| Contract | Enforced by | Invariant |
|----------|-------------|-----------|
| Import transform shape | `assert_transform_result_contract()` | result is `list(wide_raw, long_raw)`, both `data.table` |
| Export paths shape | `assert_export_paths_contract()` | `list(processed_paths, lists_paths)`, both non-empty named char vectors |
| Standardize output | `test-standardize-units.R` + `scripts/test_assignment_and_standardization_contracts.R` | `apply_standardize_rules()` returns `list(data, matched_count, unmatched_count, matched_rule_counts)` where `matched_rule_counts` is a `data.table` |
| Audit subtree | `test-setup.R` + `scripts/test_setup_directory_creation_contracts.R` | `create_required_directories()` creates audit subtree (`audit/`, `diagnostics/`, `templates/`, `runtime_cache/`) |
| Export layer detection | `test-export-data.R` | `collect_layer_tables_for_export()` detects `_raw/_clean/_normalize/_harmonize`, excludes `_wide_raw`/`_post_processed`; only `harmonize` exported by default |

## Data layout (gitignored, under `data/`)

- `data/1-import/` — `10-raw_import` (input `.xlsx`), then `11-clean` / `12-standardize` / `13-harmonize`.
- `data/2-postpro/` — `audit`, `diagnostics`, `templates`, `runtime_cache`.
- `data/3-export/` — `processed_data` (**TSV**), `lists` (**xlsx** `unique_*.xlsx`).
