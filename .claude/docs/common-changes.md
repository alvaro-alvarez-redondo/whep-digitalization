# Common changes

Touch-point recipes for the edits that come up most. Each lists **where** the logic lives,
**what** to change, the **tests** to update, and **watch-outs**. The goal is to make these
changes without rescanning the tree — if a recipe sends you somewhere that no longer
matches the code, fix the recipe.

See [codebase-map.md](codebase-map.md) for the function index,
[constants-and-options.md](constants-and-options.md) for the constant/option surface, and
[conventions.md](conventions.md) for run/test and load-order rules.

---

## Add or change a constant / threshold

- **Where:** `r/0-general_pipeline/01-setup/01-constants.R` (the only place literals belong).
- **What:** add/edit the key; access it via `get_pipeline_constants()$<path>`. Never hard-code
  the literal at the call site — see [../guidelines/constants.md](../guidelines/constants.md).
- **Tests:** `tests/0-general_pipeline/test-setup.R` asserts a set of required keys and pins
  some exact values (e.g. `sorting$stage_row_order`, `postpro$runtime_cache$enabled`). Update
  it if you change a pinned value.
- **Docs:** mirror the change in [constants-and-options.md](constants-and-options.md).

## Add a column to the canonical schema

Adding a business column ripples through several constants. Touch all that apply:

- **Canonical order** — `constants$sorting$stage_row_order` (drives `sort_pipeline_stage_dt()`
  and the import consolidation order).
- **Column role** — add it to the right group in `constants$columns`: `base` (required;
  becomes `config$column_required`), `id` (identifier; becomes `config$column_id`), `value`,
  or `system`. **Import header recognition uses `base ∪ id`** (`read_excel_sheet()` in
  `r/1-import_pipeline/11-reading/11-sheet-read.R`), so a column only gets matched/renamed
  from source headers if it is in `base` or `id`.
- **Source aliases** — if the column arrives under other header names, add them to
  `constants$header_normalization$canonical_aliases` (this is how `country → polity` works).
- **Validation** — required columns (`base`) are checked by `validate_mandatory_fields_dt()`
  (`r/1-import_pipeline/13-output/13-validate.R`); no change needed beyond the group choice.
- **Export lists** — add it to `constants$export_config$lists_to_export` if it should get a
  `unique_*.xlsx` workbook.
- **Tests:** update the exact `stage_row_order` assertion in `test-setup.R`; add transform/
  validate coverage in `tests/1-import_pipeline/`.
- **Watch out:** everything is character-typed; don't introduce numeric coercion.

## Add or change a post-processing rule behavior

- **Where:** rule matching/application lives in `r/2-postpro_pipeline/23-postpro_rule_engine/`
  (`apply_rule_payload`, `match_rule_target_condition_values`,
  `apply_target_updates_with_strategy`); the multi-pass driver is in
  `22-clean_harmonize_data/` (`run_rule_stage_layer_batch`).
- **Rule file schema** — the six canonical columns (`get_canonical_rule_columns()` in
  `21-postpro_utilities/21-stage-definitions.R`): `column_source`, `value_source_raw`,
  `value_source`, `column_target`, `value_target_raw`, `value_target`. Rule workbooks/CSVs
  are discovered from the import `clean`/`harmonize` directories; templates are produced by
  `generate_postpro_rule_templates()`.
- **Stages** — `clean` and `harmonize` (`get_postpro_stage_names()`). Multi-pass settings
  (max 10 passes, `cycle_policy = "warn"`) live under `constants$postpro$multi_pass`.
- **Matching knobs** — wildcard token `__ANY__`; columns excluded from matching
  (`year/value/yearbook/document`); update strategies `last_rule_wins` (default) and
  `concatenate` (`notes`). All under `constants$postpro`.
- **Tests:** `tests/2-post_processing_pipeline/test-rule-engine.R`,
  `test-clean-harmonize.R`; keep the contract tests in `tests/testthat/scripts/` in sync.

## Change unit standardization

- **Where:** `r/2-postpro_pipeline/24-standardize_units/`. Rules loaded by
  `load_units_standardization_rules()`, prepared by `prepare_standardize_rules()`, applied by
  `apply_standardize_rules()`.
- **Contract:** `apply_standardize_rules()` must return
  `list(data, matched_count, unmatched_count, matched_rule_counts)` with **`matched_rule_counts`
  as a `data.table`** — the audit and diagnostics depend on it. Do not change this shape
  without updating `test-standardize-units.R` and
  `scripts/test_assignment_and_standardization_contracts.R`.
- **Watch out:** a leading numeric multiplier in a unit string (e.g. `"1000 head"`) is
  extracted and folded into the value.

## Add an exported list column or change export output

- **Where:** export stage `r/3-export_pipeline/`. Processed data → **TSV**
  (`30-processed_data`, `data.table::fwrite(sep="\t")`); unique lists → **xlsx**
  (`31-lists`, `writexl::write_xlsx`).
- **What:** which columns become unique-list workbooks = `constants$export_config$lists_to_export`;
  which layers are exported = `constants$export_config$export_layers` (default `harmonize`
  only). Layer detection (`collect_layer_tables_for_export()`) accepts
  `_raw/_clean/_normalize/_harmonize`, excludes `_wide_raw`/`_post_processed`.
- **Tests:** `tests/3-export_pipeline/test-export-data.R`, `test-export-lists.R`.

## Add a helper function

- **Where:** drop a new `02-<name>.R` file in `r/0-general_pipeline/02-helpers/`. It is sourced
  automatically (alphabetically) — no constants change. See
  [conventions.md](conventions.md#adding-a-script) for the full add-a-script rules and the
  stage-vs-subdirectory distinction.

## Add or fix a test

- **Where:** the matching per-stage directory under `tests/` (`0-general_pipeline`,
  `1-import_pipeline`, `2-post_processing_pipeline`, `3-export_pipeline`). Contract tests that
  must survive refactors go in `tests/testthat/scripts/`.
- **How to run:** use the `autocode.toml` `[metrics.tests]` command (sources
  `tests/test_helper.R`, runs all five suite dirs). `tests/testthat/test_all.R` is currently
  broken — see [conventions.md](conventions.md#running-tests).
- **Watch out:** use in-memory fixtures and `build_temp_dir()`; no network or real-filesystem
  side effects; seed any randomness.

---

## Boundaries (what this repo is *not*)

- **No installed package** — code is `source()`d; load order matters (see conventions).
- **No CI** — there is no `.github/workflows`; tests are run manually.
- **`data/` is gitignored** — inputs/outputs are not in version control.
- **No backward-compatibility layer** — remove legacy patterns rather than preserving them.
