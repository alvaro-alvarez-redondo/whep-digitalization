---
name: constants
description: Centralize hard-coded literals into the 01-setup constants module.
---

# Constants & hard-coded literals

Use this when removing hard-coded values. All centralized constants live in
`r/0-general_pipeline/01-setup/01-constants.R` and are reached via
`get_pipeline_constants()` (see [../docs/architecture.md](../docs/architecture.md)).

## Mandatory actions

- Scan for paths, thresholds, URLs, magic numbers, repeated strings, and environment
  settings.
- Move them into `01-constants.R` and reference them through `get_pipeline_constants()`.
- Remove the resulting backward-compatibility scaffolding; keep only the modernized path.
- Ensure tests pass.

## Constraints

- Preserve the public API surface.
- Deterministic behavior only.
