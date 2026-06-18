# Autocode

Autonomous code optimization loop. Same idea as autoresearch but for general codebases: you modify the source code, run the scoring harness, keep improvements, discard regressions, repeat indefinitely.

## Detect the project

Before starting, understand what you're working with:

1. **Language & toolchain**: Look at the project structure to identify the language, build system, and test runner.
2. **Test suite**: Find existing tests. If none exist, tell the user — you need at least one measurable metric to optimize against.
3. **Benchmarks**: Look for performance benchmarks. If none exist but the user wants performance optimization, you'll create a simple one during setup.
4. **Linting/quality tools**: Check for eslint, ruff, pylint, clippy, golangci-lint, etc.

### Supported project types (auto-detected)

| Language | Test command | Benchmark | Quality |
|----------|-------------|-----------|---------|
| Python | `pytest` / `unittest` | `pytest --benchmark` / `time` | `ruff check` / `pylint` |
| JavaScript/TS | `npm test` / `vitest` / `jest` | `vitest bench` / custom | `eslint` |
| Rust | `cargo test` | `cargo bench` | `cargo clippy` |
| Go | `go test ./...` | `go test -bench .` | `golangci-lint run` |
| Java | `mvn test` / `gradle test` | JMH | `checkstyle` |
| Other | User specifies | User specifies | User specifies |

If the project doesn't match any of these, ask the user for the three commands: run tests, run benchmarks, run quality checks.

## Setup phase

1. **Agree on a run tag** (e.g. `jun18`). Branch `autocode/<tag>` must not exist.
2. **Create the branch**: `git checkout -b autocode/<tag>`
3. **Read the codebase**. Understand the architecture, the hot paths, what the tests cover.
4. **Create `autocode.toml`** — the configuration file that defines what to measure:

```toml
[project]
language = "python"  # or js, rust, go, java, other
source_files = ["src/**/*.py"]  # files the agent can modify
read_only = ["tests/**", "benchmarks/**"]  # files the agent cannot modify

[metrics]
# Each metric has a command, how to parse the result, and its weight in the composite score.
# At least one metric is required.

[metrics.tests]
command = "pytest --tb=short -q 2>&1"
parser = "pytest"  # built-in parser, or "regex" with a pattern
weight = 0.4
direction = "up"  # higher is better

[metrics.performance]
command = "python benchmarks/bench.py 2>&1"
parser = "regex"
pattern = "ops/sec:\\s+([\\d.]+)"
weight = 0.3
direction = "up"

[metrics.quality]
command = "ruff check src/ --statistics 2>&1"
parser = "ruff"
weight = 0.2
direction = "down"  # fewer issues is better

[metrics.complexity]
command = "python -m radon cc src/ -a -nc 2>&1"
parser = "regex"
pattern = "Average complexity: ([A-F]) \\(([\\d.]+)\\)"
weight = 0.1
direction = "down"
```

5. **Run each metric command** on unmodified code to establish baseline. Parse the output yourself — you don't need an external scoring script. For each metric:
   - Run the command
   - Parse the output to extract the score (pass rate, issue count, timing, etc.)
   - Normalize to 0-100
   - Compute the weighted composite
6. **Initialize `results.tsv`** with the baseline row.
7. **Confirm and go**.

If the user doesn't have benchmarks or linting set up, simplify — even just `tests` with weight 1.0 is enough to run the loop. You can add metrics incrementally.

## What you CAN modify

- Any file matching `source_files` in `autocode.toml`. Architecture, algorithms, data structures, error handling, performance — everything is fair game.
- `autocode.toml` — only during setup, not during the loop.

## What you CANNOT modify

- Files matching `read_only` — tests, benchmarks, and the scoring harness are the ground truth.
- Do NOT install new dependencies unless the user explicitly approves.

## Metrics

You compute a normalized composite score (0-100) by running each metric command and parsing the output:

- **Test pass rate** — run the test command, count passed/failed, compute %. This is usually the highest-weight metric because breaking tests is never acceptable.
- **Performance** — run the benchmark command, extract timing/throughput via the regex pattern. Only meaningful if benchmarks exist.
- **Code quality** — run the linter, count issues. Score = max(0, 100 - issue_count). Lower issues is better.
- **Complexity** — run the complexity tool, extract the score. Lower is better.

Each metric is normalized to 0-100 and weighted according to `autocode.toml`. The composite is the weighted sum.

**Critical rule**: if test pass rate drops below the baseline, the experiment is always discarded regardless of other improvements. You can't trade correctness for speed.

### How to parse common tools

**pytest**: Look for `X passed, Y failed` in output. Pass rate = X / (X + Y) * 100.

**jest/vitest**: Look for `Tests: X passed, Y failed`. Same formula.

**cargo test**: Look for `X passed; Y failed`. Same formula.

**go test**: Count `--- PASS:` and `--- FAIL:` lines.

**ruff/eslint**: Count violation lines. Score = max(0, 100 - count).

**Custom benchmarks**: Use the regex pattern from `autocode.toml` to extract the number.

## Logging results

Log every experiment to `results.tsv` (tab-separated):

```
commit	composite	tests	performance	quality	complexity	status	description
```

- Use 0.0 for metrics that aren't configured or that crashed.
- status: `keep`, `discard`, or `crash`

## The experiment loop

LOOP FOREVER:

1. **Assess.** Read `results.tsv` and the current source code. What's been tried? What's the weakest metric? Where's the opportunity?
2. **Hypothesize.** What specific change will improve the score, and why?
3. **Edit source files.** One focused change per experiment.
4. **Commit.** `git add -A && git commit -m "<description>"`
5. **Run each metric command.** Redirect output: `command > run.log 2>&1`
6. **Parse results yourself.** Extract pass rates, timing, lint counts from the output. Compute the composite score.
7. **Handle failures.** If a command crashed, check `tail -n 50 run.log`. Fix simple bugs, skip broken ideas.
8. **Log to results.tsv.**
9. **Keep or discard:**
   - Composite improved AND test pass rate >= baseline → keep
   - Otherwise → `git reset --hard HEAD~1`

## Strategy by optimization goal

### Improving test pass rate
- Read the failing test to understand exactly what it expects
- Fix one test at a time — don't try to fix everything at once
- If a fix for test A breaks test B, revert and try a different approach
- Look for patterns in failures: are they all related to the same module?

### Performance optimization
- Profile first. If the language has a profiler (cProfile, perf, flamegraph), run it to find the hot path
- Common wins: algorithm complexity reduction (O(n²) → O(n log n)), caching, avoiding unnecessary allocations, batch I/O
- Measure before and after — gut feelings about performance are often wrong
- Don't micro-optimize. Focus on algorithmic improvements, not shaving cycles

### Code quality
- Start with auto-fixable issues: `ruff check --fix`, `eslint --fix`, `cargo clippy --fix`
- Then tackle structural issues: long functions, deep nesting, unclear naming
- Remove dead code — it always improves quality scores and simplifies the codebase

### Algorithm optimization
- Read the existing implementation carefully before changing it
- Start with the obvious improvements (use a set instead of a list for lookups, etc.)
- Try well-known algorithms for the problem class
- Always verify correctness via tests before evaluating performance

## Decision principles

- **Tests are sacred.** Never accept a change that reduces test pass rate below baseline.
- **One idea per experiment.** If you change three things and it improves, you don't know which helped.
- **Simplicity wins.** Equal score, fewer lines → keep the simpler version.
- **Don't chase noise.** For performance benchmarks especially, small variations may be measurement noise. Look for >5% improvements.
- **Compound small wins.** A 2% improvement per experiment adds up over 50 experiments.

## Timeout

Set a timeout per experiment based on how long the test suite takes. If tests take 30 seconds, budget 2 minutes per experiment (including edit + commit + scoring overhead). If a run exceeds 3x the expected time, kill it and treat as crash.

## NEVER STOP

Once the loop begins, do NOT pause to ask the human. If you run out of ideas: re-read the code with fresh eyes, look at test output for clues, try approaches that failed before but with a different twist, try combining two small improvements that individually didn't move the needle. The loop runs until the human stops you.

## Progress reporting

Every 10 experiments, or when you achieve a notable improvement, write a brief summary to `progress.md`:

```markdown
## Experiment 10-20 summary
- Best composite: 82.3 (up from 78.5 baseline)
- Key wins: switched sorting algorithm (+3.2), removed redundant DB query (+1.1)
- Current bottleneck: test_integration_auth still failing
- Next ideas: connection pooling, caching user lookups
```

This gives the human a quick overview when they return.
