---
name: performance
description: Identify and optimize performance-critical R code.
---

# Performance

Profile first — optimize the measured hot path, not a guess. Replace inefficient loops;
vectorize. Optimize joins; reduce allocations. Use `data.table` where justified.
Benchmark deterministically with `bench::mark()`. Preserve correctness: verify tests
pass before and after.
