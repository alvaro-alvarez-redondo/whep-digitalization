# Autocode

Autonomous code optimization loop: modify source → score → keep improvements → discard
regressions → repeat indefinitely.

## This project

R pipeline (`language = "r"`). Configuration in `autocode.toml` (repo root):

- **Source files:** `r/**/*.R` — **Read-only:** `tests/**/*.R`, `perf/**/*.R`
- **Metrics:** tests (weight 0.5, up) + performance (weight 0.5, down — `PIPELINE_SECONDS`
  from `perf/autocode_bench.R`, 120k-row subset, min 2 reps)

**Skip project detection and setup.** Go straight to the experiment loop. Read
`.claude/progress.md` and `.claude/results.tsv` for current state.

### Known constraints (from `.claude/progress.md`)

- Import is bounded by readxl C code — only parallelism helps (already auto-enabled)
- Postpro optimized through jun24 (~1.76x faster); remaining hot paths are inherent
- Performance metric is import-dominated; diminishing returns — focus on tests or code
  quality unless a genuine algorithmic opportunity emerges

### State files — update both every session

- `.claude/results.tsv` — append one row per experiment (format:
  `commit	composite	tests_passed	tests_failed	pass_rate	status	description`;
  status: `baseline`/`keep`/`discard`/`crash`/`validate`/`feature`)
- `.claude/progress.md` — update "Current state"; add to "Optimization boundaries" if new
  limits found; append session summary to "Session archive"

## What you can/cannot modify

- **Can:** any file matching `source_files` in `autocode.toml`
- **Cannot:** files matching `read_only` (tests, benchmarks). Do not install new
  dependencies without explicit user approval.

## The experiment loop

LOOP FOREVER:

1. **Assess.** Read `.claude/results.tsv` and current source. What's been tried? Weakest
   metric? Where's the opportunity?
2. **Hypothesize.** What specific change will improve the score, and why?
3. **Edit source files.** One focused change per experiment.
4. **Commit.** `git add -A && git commit -m "<description>"`
5. **Run each metric command.** Parse results — extract pass rates, timing.
6. **Handle failures.** If crashed, check output. Fix simple bugs, skip broken ideas.
7. **Log to `.claude/results.tsv`.**
8. **Keep or discard:** composite improved AND test pass rate >= baseline → keep.
   Otherwise → `git reset --hard HEAD~1`.

## Rules

- **Tests are sacred.** Never accept a change that reduces test pass rate below baseline.
- **One idea per experiment.** Isolate variables.
- **Simplicity wins.** Equal score, fewer lines → keep simpler version.
- **Don't chase noise.** Look for >5% performance improvements.
- **Clean scratch before committing.** Run logs and one-off scripts are temporary.
- **Never stop.** Do not pause to ask the human. If stuck: re-read code, try failed
  approaches with a twist, combine small improvements. Loop until stopped.

## Progress reporting

Every 10 experiments or notable improvement, update `.claude/progress.md` with: current
best scores, key wins, bottlenecks, next ideas.
