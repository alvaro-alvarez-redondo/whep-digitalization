# CLAUDE.md

WHEP Digitalization Pipeline — script-oriented R pipeline processing WHEP source
workbooks through four stages: general bootstrap → import → post-processing → export.

## How to work

- **Act autonomously.** Make decisions when context is sufficient. Default to action, not
  confirmation. Ask only when a decision is ambiguous, irreversible, high-impact, or
  lacks information. Document assumptions.
- **Use `/autocode` by default** for optimization, test-fixing, and code-quality work.
  Use parallel agents when it improves speed or coverage.
- **Reuse project context.** Read `.claude/docs/` and `.claude/progress.md` instead of
  rescanning the codebase. These are kept current.
- **Deliver complete solutions.** Do not stop at partial progress. Iterate on complex
  refactors for efficiency, modularity, and clarity.
- **One concern per change.** Keep diffs focused; clean temporary files before committing.
  Durable results go in `.claude/progress.md` / `.claude/results.tsv`, not scratch logs.
- **Tests are ground truth.** Every behavior change ships with tests. Never lower pass rate.
- **Tone:** strict, technical. No filler.

## Reference docs (read on demand, not every session)

- [architecture.md](.claude/docs/architecture.md) — stages, data flow, entry points,
  contracts.
- [codebase-map.md](.claude/docs/codebase-map.md) — every file/function by stage (use
  instead of grepping).
- [constants-and-options.md](.claude/docs/constants-and-options.md) —
  `get_pipeline_constants()` surface and `whep.*` options.
- [conventions.md](.claude/docs/conventions.md) — run/test, load order, determinism,
  parallelism, gotchas.
- [common-changes.md](.claude/docs/common-changes.md) — recipes for frequent edits.
  **Check here first** for typical changes.
- [guidelines/](.claude/guidelines/) — task playbooks (refactoring, performance, testing,
  constants, readme-generation).

## Engineering standards

- `snake_case`, native pipe `|>`, `<-`, explicit `return()`, `roxygen2` docs.
- Validate with `checkmate`; errors/diagnostics via `cli`.
- No global state outside orchestration entry points.
- Deterministic: identical inputs + options → identical outputs. Seed randomness.
- No hard-coded literals — centralize in `01-constants.R` via `get_pipeline_constants()`.
- No backward-compatibility scaffolding — remove legacy code on sight.
- Preserve public function signatures and contracts unless modernization requires change.

## Run & test

```r
source(here::here("r", "run_pipeline.R"), local = TRUE)
run_pipeline(show_view = FALSE, pipeline_root = here::here("r"))
```

Tests: use the command in `autocode.toml` `[metrics.tests]`. Do **not** use
`tests/testthat/test_all.R` (broken). See [conventions.md](.claude/docs/conventions.md).

## Commands

- `/autocode` — autonomous optimization loop. Config: `autocode.toml`. State:
  [progress.md](.claude/progress.md), [results.tsv](.claude/results.tsv).
