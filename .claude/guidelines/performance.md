---
name: performance
description: Identify and optimize performance-critical R code.
---

# Performance

Use this when profiling and optimizing hot paths. See the performance levers
(parallelism, checkpointing, constants caching) in
[../docs/architecture.md](../docs/architecture.md).

## Mandatory actions

- Profile first — optimize the measured hot path, not a guess.
- Replace inefficient loops; vectorize computations.
- Optimize joins; reduce memory allocations.
- Use `data.table` only where justified.
- Benchmark deterministically with `bench::mark()`.

## Constraints

- Benchmarks must be deterministic and realistic.
- Preserve correctness: verify tests pass before and after (see [testing.md](testing.md)).
- Apply improvements directly and commit changes.
