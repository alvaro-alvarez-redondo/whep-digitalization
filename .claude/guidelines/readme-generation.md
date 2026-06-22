---
name: readme-generation
description: Generate a production-grade README.md reflecting the post-refactor state.
---

# README generation

Use this when regenerating the project `README.md` to reflect the current repository state.

## Mandatory structure (fixed order)

1. Project Title
2. Technical Description
3. Installation (`renv` enforced)
4. Dependency Management
5. Quick Start (deterministic example)
6. Exported API Overview
7. Architecture Overview
8. Engineering Standards
9. Performance Notes (if benchmarks exist)
10. Reproducibility & Determinism
11. Testing & Coverage
12. CI/CD
13. Backward Compatibility Policy (state the removal of legacy behavior)
14. Contributing
15. License

## Style

- Strict technical tone; no marketing language, no emojis.
- Markdown-compliant, valid GitHub rendering.

## Implementation

- Generate the full `README.md`, replace the existing file, and commit changes.
- Keep the Architecture Overview consistent with
  [../docs/architecture.md](../docs/architecture.md).
