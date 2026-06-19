---
name: iterative-optimization
description: 'Encourage iterative and deep analysis for complex R refactor or performance tasks.'
---

## Purpose
For large or complex tasks—especially refactoring, performance improvements, or optimization—the AI must perform **multiple iterative passes**, deeply analyzing and evaluating alternatives to produce the **most efficient and robust result**. 

## Key Rules

1. **Iterative Approach**
   - Analyze the task in multiple stages; identify inefficiencies, redundant patterns, and improvement opportunities.
   - After each iteration, reassess results, refine code, and re-evaluate performance or structure.
   - Do not stop at the first correct solution; aim for maximal efficiency and maintainability.

2. **Depth of Analysis**
   - Use all available context to reason through dependencies, data structures, and algorithmic choices.
   - Consider trade-offs in memory, computation, readability, and modularity.
   - For complex code, prioritize thorough reasoning even if it requires extended “thinking” time.

3. **Refactor and Optimize**
   - Apply transformations incrementally, verifying correctness and deterministic behavior at each step.
   - Explicitly eliminate legacy or inefficient patterns.
   - Ensure all improvements align with modern R practices: snake_case, native pipe `|>`, `<-` assignment, modular structure.

4. **Evaluation and Feedback**
   - After each pass, evaluate improvements: performance metrics, code clarity, test coverage, and modularity.
   - Document decisions and trade-offs in reasoning.
   - Repeat iterations until no further meaningful gains can be identified.

5. **Output**
   - Present a final optimized or refactored version with a **technical rationale for each key change**.
   - Include an audit of iterations showing how each pass improved efficiency, modularity, or readability.

## Scope
- Applies to **refactor tasks, performance optimization, and large-scale code improvements**.
- Deterministic tasks only; all changes must be reproducible.
- Can be applied to any R script, package module, or project-wide refactoring task.

## Example Prompts
- “Refactor this module to maximize efficiency and readability; iterate until fully optimized.”
- “Analyze all loops and vectorize wherever possible, performing multiple passes for the best result.”
- “Optimize memory usage and computation time for this function with deep iterative reasoning.”
