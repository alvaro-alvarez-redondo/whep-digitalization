# Autocode Progress — jun18

## Baseline
- Composite: 92.5 (506 passed, 41 failed)
- Root cause: `source_postpro_scripts()` only called inside `run_postpro_pipeline_batch()`, not at module load time. Tests that directly call post-processing functions get "could not find function" errors.
- Failing suites: `2-post_processing_pipeline` (36 failures), `testthat/scripts` (5 failures)
