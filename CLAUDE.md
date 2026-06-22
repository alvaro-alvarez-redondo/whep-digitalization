# CLAUDE.md

Project memory for the **WHEP Digitalization Pipeline** — a script-oriented R pipeline
that processes WHEP source workbooks through deterministic stages (general bootstrap →
import → post-processing → export). This file is loaded automatically into every Claude
session. Read it before editing.

## Before you edit

Prefer reading these docs over rescanning the codebase — they are kept current on purpose:

1. [.claude/docs/architecture.md](.claude/docs/architecture.md) — **start here**: stage
   layout, data flow, entry points, and the contracts you must not break.
2. [.claude/docs/codebase-map.md](.claude/docs/codebase-map.md) — every file and function,
   by stage. Use it as a lookup index instead of grepping.
3. [.claude/docs/constants-and-options.md](.claude/docs/constants-and-options.md) — the
   full `get_pipeline_constants()` surface and all `whep.*` option flags.
4. [.claude/docs/conventions.md](.claude/docs/conventions.md) — how to run & test, load
   order, determinism, parallelism, and gotchas.
5. [.claude/docs/common-changes.md](.claude/docs/common-changes.md) — touch-point recipes
   for frequent edits (add a column, rule, constant, export, or test). Check here first
   when making a typical change.

For a specific kind of task, also read the matching playbook in
[.claude/guidelines/](.claude/guidelines/) (refactoring, performance, testing, constants,
readme-generation). The full map of this layer is in [.claude/README.md](.claude/README.md).

## Engineering standards (always apply)

- **Style:** `snake_case` names, native pipe `|>`, `<-` assignment, explicit `return()` in
  functions, function-level `roxygen2` documentation inside scripts.
- **Validation:** validate inputs with `checkmate`; surface diagnostics and errors through
  `cli`.
- **No global state:** outside the orchestration entry points, do not introduce implicit
  global-state dependencies.
- **Determinism:** identical inputs and options must produce identical outputs. Seed any
  randomness. No network or filesystem side effects in library code.
- **No hard-coded literals:** paths, thresholds, URLs, magic numbers, and repeated strings
  belong in `r/0-general_pipeline/01-setup/01-constants.R`, reached via
  `get_pipeline_constants()`. See [.claude/guidelines/constants.md](.claude/guidelines/constants.md).
- **No backward-compatibility scaffolding:** there are no consumers to protect. Remove
  legacy patterns, wrapper files, and dead code when you find them — do not preserve them.
- **Stable contracts:** preserve public function signatures, return types, and output
  schemas unless a modernization genuinely requires changing them. The enforced contracts
  are listed in the architecture doc.

## How to work

- **Deterministic, scoped changes only.** One concern per change; keep diffs focused.
- **Tests are the ground truth.** Every behavior or contract change ships with updated or
  new `testthat` tests. Never accept a change that lowers the test pass rate. See
  [.claude/guidelines/testing.md](.claude/guidelines/testing.md).
- **Iterate on complex refactors.** Do not stop at the first correct version; reassess for
  efficiency, modularity, and clarity. See
  [.claude/guidelines/refactoring.md](.claude/guidelines/refactoring.md).
- **Tone:** strict and technical. No marketing language, no conversational filler in code,
  comments, or docs.

## Commands

- `/autocode` — autonomous optimization loop (run tests → keep improvements → discard
  regressions). Config in `autocode.toml`; run state in `progress.md` and `results.tsv`.
  See [.claude/commands/autocode.md](.claude/commands/autocode.md).

## Run & test (quick reference)

```r
# Run the pipeline
source(here::here("r", "run_pipeline.R"), local = TRUE)
run_pipeline(show_view = FALSE, pipeline_root = here::here("r"))
```

Run the tests with the command in `autocode.toml` (`[metrics.tests]`), which sources
`tests/test_helper.R` and runs all five suite directories. Note: `tests/testthat/test_all.R`
is currently broken — see [.claude/docs/conventions.md](.claude/docs/conventions.md#running-tests).
