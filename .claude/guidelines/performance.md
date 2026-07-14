---
name: performance
description: Identify and optimize performance-critical R code.
---

# Performance

Profile first — optimize the measured hot path, not a guess. Replace inefficient loops;
vectorize. Optimize joins; reduce allocations. Use `data.table` where justified.
Benchmark deterministically with `bench::mark()`. Preserve correctness: verify tests
pass before and after.

The committed benchmark ground truth is `.claude/bench/autocode_bench.R` (read-only). Any
*ad-hoc* profiling or benchmark harness you write, along with the CSV/RDS/log output it
emits, is temporary. **Delete each as soon as it is no longer needed** — do not commit it
and do not defer cleanup to commit time. Keep such scratch in a session-local temp dir or a
gitignored `*.out` path while in use. Fold durable findings into `.claude/progress.md`. See
the temp-file policy in [conventions.md](../docs/conventions.md).
