# Common changes

Recipes for frequent edits. Each lists where, what, tests, and watch-outs.

---

## Add or change a constant / threshold

- **Where:** `r/0-general_pipeline/01-setup/01-constants.R`.
- **What:** add/edit key; access via `get_pipeline_constants()$<path>`.
- **Tests:** `tests/0-general_pipeline/test-setup.R` (pins some exact values).
- **Docs:** mirror in `constants-and-options.md`.

## Add a column to the canonical schema

- **Canonical order** — `constants$sorting$stage_row_order`.
- **Column role** — add to `constants$columns`: `base`, `id`, `value`, or `system`.
  Import header recognition uses `base ∪ id`.
- **Source aliases** — `constants$header_normalization$canonical_aliases`.
- **Export lists** — `constants$export_config$lists_to_export` if needed.
- **Tests:** update `stage_row_order` assertion in `test-setup.R`; add transform/validate
  coverage.
- **Watch out:** everything character-typed.

## Add or change a post-processing rule behavior

- **Where:** `r/2-postpro_pipeline/23-postpro_rule_engine/` (matching/application);
  `22-clean_harmonize_data/` (multi-pass driver).
- **Rule schema** — 6 canonical columns from `get_canonical_rule_columns()`:
  `column_source`, `value_source_raw`, `value_source`, `column_target`,
  `value_target_raw`, `value_target`.
- **Stages:** `clean` and `harmonize`. Multi-pass: max 10, `cycle_policy = "warn"`.
- **Matching:** wildcard `__ANY__`; strategies `last_rule_wins` (default), `concatenate`.
- **Tests:** `test-rule-engine.R`, `test-clean-harmonize.R`; keep contract tests in sync.

## Change unit standardization

- **Where:** `r/2-postpro_pipeline/24-standardize_units/`.
- **Contract:** `apply_standardize_rules()` → `list(data, matched_count, unmatched_count,
  matched_rule_counts)` with `matched_rule_counts` as `data.table`.
- **Watch out:** leading numeric multiplier in unit strings folded into value.

## Add an exported list column or change export output

- **Where:** `r/3-export_pipeline/`. Processed → TSV; lists → xlsx.
- **What:** `constants$export_config$lists_to_export` (columns), `export_layers` (default
  `harmonize`). Layer detection excludes `_wide_raw`/`_post_processed`.
- **Tests:** `test-export-data.R`, `test-export-lists.R`.

## Add a helper function

Drop `02-<name>.R` in `r/0-general_pipeline/02-helpers/` — auto-sourced alphabetically.

## Add or fix a test

- **Where:** matching per-stage dir under `tests/`. Contract tests in
  `tests/testthat/scripts/`.
- Use in-memory fixtures + `build_temp_dir()`; seed randomness; no side effects.

---

## Boundaries

- No installed package — `source()`d; load order matters.
- No CI — tests run manually.
- `data/` is gitignored.
- No backward-compatibility — remove legacy patterns.
