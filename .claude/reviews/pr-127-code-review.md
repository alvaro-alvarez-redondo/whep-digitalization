# Code Review — PR #127 (`autocode jul4/jul5`)

**Scope reviewed:** full diff `main` (`219bc256`) → `autocode/jul4` (`93d4539`), 37 files,
+3545/−1815. Covered by four parallel per-subsystem reviews (import read/transform +
vectorized validation; postpro rule engine; postpro standardize/diagnostics/cache;
general/progress/constants/export), each tracing concrete inputs against the base code.

**Companion patch:** `.claude/reviews/pr-127-code-review.patch` — applies onto the PR head
(`git apply` verified). It carries only the fixes below; nothing is pushed to the PR.

## Verdict

No **critical/high** correctness bugs. The two highest-risk claims hold up under detailed
tracing:

- **Vectorized `validate_long_dt_by_document`** (`13-validate.R`) is output-identical to the
  old `split(by="document")` + per-document loop across every axis: document-major reorder
  (stable radix), mandatory/year/duplicate ordering, `key_descriptions` string assembly, the
  empty-input `errors = NULL` shape, and the `(2*nfiles)+4` progress budget.
- **Lazy cycle-detection / state-record fingerprinting** is sound: the fingerprint is a pure
  function of the data (equal data ⟹ equal fingerprint, so no real cycle is screened out),
  collisions correctly fall through to exact byte compare, and `data.table::copy()` at
  snapshot time prevents `:=` aliasing. New tests cover the collision fallthrough.
- **File splits** (23-*, 24-*, 25-*) are byte-identical function moves; auto-sourcing and
  load order are preserved; no symbol dropped.
- **NA-footnote audit fix** is correct: `strsplit(NA, ";")` already emits one NA token, so
  the removed `na_rows` append was pure double-counting — data byte-identical, `affected_rows`
  corrected (halved) on the 4 clean-audit NA-source rows, and NA-matching rules still fire.

The patch addresses latent-correctness and determinism items; the rest are notes.

## Findings addressed by the patch

### 1. Fused import pairs metadata by value-`match`, not by position — latent regression
`r/1-import_pipeline/12-transform/12-processing.R:216` · correctness/robustness · verdict: PLAUSIBLE (masked today)

`read_transform_pipeline_files` resolves each batch's metadata with
`batch_indices <- match(batch_paths, file_paths)`. `match` returns the **first** index for a
repeated path, whereas the old `process_files` paired metadata to read data strictly by row
position (`file_list_dt[i]`, `i in seq_len(nrow)`). If `file_list_dt` ever contains the same
`file_path` twice with distinct metadata (one workbook mapped to two commodities/yearbooks),
the duplicate row is transformed with the **wrong** `commodity`/`yearbook`/`file_name`. Not
reachable today because `discover_files` (`fs::dir_ls`) yields unique paths — hence a
defensive fix. **Patch:** derive positional row indices from the (contiguous) batch structure
and `Map` them onto the batches, restoring per-row pairing. Output-identical for unique paths.

### 2. Header-alias guard dedupes targets but not duplicate sources
`r/1-import_pipeline/11-reading/11-header-normalization.R:236` · edge-case · verdict: PLAUSIBLE

`alias_keep <- !(alias_old %in% old_names) & !duplicated(alias_new)` blocks two aliases from
claiming the same *new* name, but not two aliases resolving (via `normalize_header_names` +
`match`) to the same *source* column — that hands `setnames(old, new)` a duplicated `old` and
renames unpredictably. **Patch:** add `& !duplicated(alias_old)`.

### 3. Export sheet/script ordering still uses locale-dependent `sort()`
`r/3-export_pipeline/30-processed_data/02-collect-layer-tables.R:74,80` and
`r/3-export_pipeline/run_export_pipeline.R:61` · determinism · verdict: CONFIRMED (locale-dependent)

The PR explicitly establishes a locale-independent (radix) determinism contract and converts
the `31-lists` sorts, but these sibling sorts that order exported sheets and sourced scripts
remain bare `sort()` (session `LC_COLLATE`). These sites are **pre-existing** (not introduced
by this PR); the patch converts them to `method = "radix"` to complete the contract. Real-world
impact is small (ASCII snake_case names), so this is a consistency/robustness fix.

## Notes (not patched — author's call)

- **PR description accuracy.** Three functions are *not* "pure behavior-identical moves":
  `apply_footnote_rules` (the intentional NA fix), `build_conditional_rule_dictionary` (added
  `method = "radix"`, an intended determinism change that can flip which conflicting rule wins
  on accented/mixed-case Spanish targets), and the `apply_rule_payload` else-branch (an
  equivalent dedup refactor). Worth wording the description accordingly. The "auto worker cap
  4→8" bullet is stale — base `219bc256` already has `import_parallel_workers_auto_max = 8L`;
  this diff only adds `import_future_scheduling = 4`.
- **`build_conditional_rule_dictionary` radix ordering** — recommend a test over a rule file
  with conflicting accented targets to pin the new last-rule-wins order.
- **`02-progress.R:193` `delay_conditions = "condition"`** buffers *all* mid-stage
  warnings/messages until stage end (changes diagnostic interleaving; possible late/lost flush
  on abort). Consider narrowing to `"message"` or documenting the intent. No data impact.
- **`02-progress.R:224` palette code-as-strings** built with `eval(parse(...))` per console
  line is fragile (a stage label with a `'`, or a malformed palette value, errors at render
  time) and re-parses each line. Consider storing cli style functions directly. Interactive
  path only.
- **`21-template-rules.R` Excel `col_types = "text"`** renders real Excel *date-typed* rule
  cells as serial-number strings (`"44197"`), not `"2021-01-01"`. The comment only claims
  numeric-code preservation (accurate), so nothing is misdescribed — flagged only in case rule
  files ever carry date-typed cells in match columns.
- **Pre-existing latent issues the PR's own notes document** (out of scope, unfixed): the
  "column not present" abort is dead when a `column_source` typo + blank `value_source_raw`
  keys `NA == NA`; footnote-engine audit can suppress rows for `column_target != "footnotes"`
  rules so their target updates apply unaudited; `audit_numeric_string` regex false-positives
  on scientific notation (audit-report noise only).

## How to apply

```sh
git checkout autocode/jul4
git apply .claude/reviews/pr-127-code-review.patch   # or: git apply -3 for a 3-way merge
```

Findings are independent — drop any hunk you don't want before applying.
