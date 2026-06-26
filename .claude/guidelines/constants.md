---
name: constants
description: Centralize hard-coded literals into the 01-setup constants module.
---

# Constants

Scan for paths, thresholds, URLs, magic numbers, repeated strings. Move them into
`r/0-general_pipeline/01-setup/01-constants.R` and reference via
`get_pipeline_constants()`. Remove backward-compat scaffolding. Ensure tests pass.
Preserve public API surface. Deterministic behavior only.
