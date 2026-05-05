# WHEP Digitalization Pipeline

## 1. Project Title

WHEP Digitalization Pipeline

## 2. Technical Description

This repository is a script-oriented R pipeline that processes WHEP source workbooks through deterministic stages:

1. General bootstrap (dependency checks, configuration construction, directory preparation)
2. Import (file discovery, read, transformation, validation)
3. Post-processing (audit, cleaning, unit standardization, harmonization)
4. Export (processed layer workbooks and unique-list outputs)

Execution is orchestrated by `R/run_pipeline.R`, which sources stage runners in fixed order.

## 3. Installation (renv enforced)

### Prerequisites

- R >= 4.1
- `renv`

### Setup

```r
install.packages("renv")
renv::init(bare = TRUE)
renv::install(c(
  "checkmate", "cli", "data.table", "dplyr", "fs", "future", "future.apply",
  "here", "openxlsx", "progressr", "purrr", "readr", "readxl", "stringi",
  "stringr", "testthat", "withr"
))
renv::snapshot()
```

## 4. Dependency Management

- Runtime dependencies are organized under `r/0-general_pipeline/00-dependencies/`.
- Core configuration constants live in `r/0-general_pipeline/01-setup/01-constants.R`.
- Configuration and directory constructors live in `r/0-general_pipeline/01-setup/01-config.R` and `r/0-general_pipeline/01-setup/01-directories.R`.
- Shared helpers are organized under `r/0-general_pipeline/02-helpers/`.
- Dependency installation and version locking are expected to be managed via `renv`.

## 5. Quick Start (deterministic example)

```r
source(here::here("r", "run_pipeline.R"), local = TRUE)

options(
  whep.run_pipeline.auto = FALSE,
  whep.run_general_pipeline.auto = FALSE,
  whep.run_import_pipeline.auto = FALSE,
  whep.run_postpro_pipeline.auto = FALSE,
  whep.run_export_pipeline.auto = FALSE
)

run_pipeline(
  show_view = FALSE,
  pipeline_root = here::here("r")
)
```

## 6. Exported API Overview

Primary API exposed via `R/run_pipeline.R`:

- `run_pipeline(show_view = interactive(), pipeline_root = here::here("r"))`

Core stage entry points used by the orchestrator:

- `run_general_pipeline(dataset_name = get_pipeline_constants()$dataset_default_name)`
- `run_import_pipeline(config)`
- `run_postpro_pipeline_batch(raw_dt, config, dataset_name, unit_column, value_column, commodity_column)`
- `run_export_pipeline(config, data_objects = NULL, overwrite = TRUE, env = .GlobalEnv)`

Auto-run wrappers:

- `run_import_pipeline_auto(auto_run, env = .GlobalEnv)`
- `run_postpro_pipeline_auto(auto_run, env = .GlobalEnv)`
- `run_export_pipeline_auto(auto_run, env = .GlobalEnv)`

Contract helpers:

- `assert_transform_result_contract(transform_result)`
- `assert_export_paths_contract(export_result)`

## 7. Architecture Overview

- `r/0-general_pipeline/`
  - `00-dependencies/`: dependency validation, installation, load, audit modules
  - `01-setup/`: constants, config, and directory modules
  - `02-helpers/`: focused helper modules by responsibility
  - `run_general_pipeline.R`: stage bootstrap
- `r/1-import_pipeline/`: file IO, reading, transforms, validation, import runner
- `r/2-postpro_pipeline/`: audit, post-processing utilities, rule engine, clean, standardize units, harmonize, diagnostics, post-processing runner
- `r/3-export_pipeline/`: processed-data and unique-list exporters, export runner
- `r/run_pipeline.R`: global orchestrator
- `tests/testthat/scripts/` and `tests/0-general_pipeline/`: deterministic `testthat` suites

## 8. Engineering Standards

- Native pipe `|>`
- Snake case naming
- `<-` assignment
- Explicit `return()` in functions
- Input validation through `checkmate`
- Structured diagnostics/errors through `cli`
- Function-level roxygen documentation in script files
- Deterministic stage ordering and deterministic output contracts

## 9. Performance & Scalability

The pipeline includes several performance optimizations for large-scale processing (1000+ files):

### Parallel Processing

File reading, transformation, and list export leverage `future.apply::future_lapply()` for parallel execution when a `future` backend is configured. By default, the pipeline runs sequentially (`future::sequential`).

Enable parallel processing:

```r
future::plan(future::multisession, workers = 4)
source(here::here("r", "run_pipeline.R"), local = TRUE)
```

When parallel backends are active, these stages run in parallel:
- **Import**: `read_pipeline_files()` reads Excel files concurrently
- **Transform**: `process_files()` transforms file data concurrently
- **Export**: `export_lists()` writes column workbooks concurrently

### Checkpointing

For long-running pipelines, optional RDS checkpointing provides crash recovery:

```r
options(whep.checkpointing.enabled = TRUE)
```

When enabled:
- Import results are saved to `data/.checkpoints/import_pipeline.rds`
- Subsequent runs skip import if a valid checkpoint exists
- Clear checkpoints: `clear_pipeline_checkpoints(config)`

### Constants Caching

`get_pipeline_constants()` caches its result after the first call, avoiding repeated list construction in hot paths throughout the pipeline.

### Memory Efficiency

- `data.table` inputs skip redundant copy+conversion in standardization rules
- Rule engine uses pre-allocated vectors instead of list-growing patterns
- `base::lapply()` replaces `purrr::map()` in performance-critical loops

## 10. Reproducibility & Determinism

- Deterministic execution order is fixed by the orchestrator.
- Centralized constants (`get_pipeline_constants()`) reduce hard-coded drift across stages.
- Data contracts are enforced with explicit assertions.
- Pipeline behavior is designed to be deterministic for identical inputs and options.

## 11. Testing & Coverage

Run all tests:

```r
source(here::here("tests", "testthat", "test_all.r"), echo = FALSE)
```

Run test directory directly:

```r
testthat::test_dir(here::here("tests", "testthat", "r"), reporter = "summary")
```

Coverage notes:

- Tests include layer detection, post-processing rule handling, schema contracts, and pipeline path validation.
- Formal coverage report artifacts are not committed in this repository.

## 12. CI/CD

No CI workflow configuration is currently committed under `.github/workflows`.

Recommended baseline CI pipeline:

1. Restore environment with `renv`
2. Execute `testthat` suite
3. Fail on any non-zero test result

## 13. Compatibility Policy

- Backward compatibility is not preserved for wrapper files or legacy loader entrypoints.
- Consumers should source the exact modules they depend on.
- Keep function signatures and return schemas stable where feasible.

## 14. Contributing

- Keep changes scoped and deterministic.
- Update/add tests with every behavior or contract change.
- Reuse centralized constants from `r/0-general_pipeline/01-setup/01-constants.R` for options, script names, and object names.
- Avoid introducing implicit global-state dependencies outside orchestration entry points.

## 15. License

No license file is currently present in the repository. Add a `LICENSE` file to define usage and redistribution terms.
