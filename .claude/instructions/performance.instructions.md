---
name: performance
description: 'Identify and optimize performance-critical code in R repository.'
---

## Mandatory Actions
- Profile performance-critical code.
- Replace inefficient loops; vectorize computations.
- Optimize joins; reduce memory allocations.
- Use `data.table` only if justified.
- Benchmark deterministically with `bench::mark()`.

## Constraints
- Benchmarks must be deterministic and realistic.

## Implementation
- Apply performance improvements directly and commit changes.