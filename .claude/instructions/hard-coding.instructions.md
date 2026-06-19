---
name: hard-coding
description: 'Centralize all hard-coded literals into the 01-setup/ modules.'
---

## Mandatory Actions
- Scan repository for paths, thresholds, URLs, magic numbers, repeated strings, environment settings.
- Refactor scripts to reference constants in `r/0-general_pipeline/01-setup/01-constants.R`.
- Ensure modernized behavior and eliminate backward compatibility constraints.
- Ensure tests pass.

## Constraints
- Preserve API surface.
- Deterministic behavior only.