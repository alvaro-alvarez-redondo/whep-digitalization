---
name: readme-generator
description: 'Generate commodityion-grade README.md reflecting post-refactor repository state.'
---

## Mandatory Structure (fixed order)
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
13. Backward Compatibility Policy (**state removal of legacy behavior**)
14. Contributing
15. License

## Style
- Strict technical tone
- Markdown compliant
- No marketing or emojis
- Valid GitHub rendering

## Implementation
- Generate full `README.md`.
- Replace existing file and commit changes.
