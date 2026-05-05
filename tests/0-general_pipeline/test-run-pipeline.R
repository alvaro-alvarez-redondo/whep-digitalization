# tests/0-general_pipeline/test-run-pipeline.R
# unit tests for R/run_pipeline.R helper utilities

source(here::here("tests", "test_helper.R"), echo = FALSE)
source(here::here("r", "run_pipeline.R"), echo = FALSE)


testthat::test_that("format_postpro_iteration_count handles valid and missing values", {
  testthat::expect_identical(format_postpro_iteration_count(2L), "2")
  testthat::expect_identical(
    format_postpro_iteration_count(NA_integer_),
    "N/A"
  )
})

testthat::test_that("extract_postpro_stage_pass_count reads stage diagnostics", {
  stage_diagnostics <- list(multi_pass = list(passes_executed = 3L))

  testthat::expect_identical(
    extract_postpro_stage_pass_count(stage_diagnostics),
    3L
  )
  testthat::expect_true(is.na(extract_postpro_stage_pass_count(list())))
})

testthat::test_that("get_postpro_iteration_loop_counts returns N/A counts when object is absent", {
  isolated_env <- new.env(parent = emptyenv())

  loop_counts <- get_postpro_iteration_loop_counts(env = isolated_env)

  testthat::expect_true(is.na(loop_counts$clean))
  testthat::expect_true(is.na(loop_counts$harmonize))
})

testthat::test_that("get_postpro_iteration_loop_counts reads clean and harmonize pass counts", {
  isolated_env <- new.env(parent = emptyenv())
  pipeline_constants <- get_pipeline_constants()
  harmonize_name <- pipeline_constants$object_names$harmonize

  harmonize_dt <- data.table::data.table(row_id = 1L)
  attr(harmonize_dt, "pipeline_diagnostics") <- list(
    clean = list(multi_pass = list(passes_executed = 2L)),
    harmonize = list(multi_pass = list(passes_executed = 4L))
  )
  assign(harmonize_name, harmonize_dt, envir = isolated_env)

  loop_counts <- get_postpro_iteration_loop_counts(env = isolated_env)

  testthat::expect_identical(loop_counts$clean, 2L)
  testthat::expect_identical(loop_counts$harmonize, 4L)
})

testthat::test_that("build_postpro_iteration_summary formats deterministic suffix", {
  isolated_env <- new.env(parent = emptyenv())
  pipeline_constants <- get_pipeline_constants()
  harmonize_name <- pipeline_constants$object_names$harmonize

  harmonize_dt <- data.table::data.table(row_id = 1L)
  attr(harmonize_dt, "pipeline_diagnostics") <- list(
    clean = list(multi_pass = list(passes_executed = 1L)),
    harmonize = list(multi_pass = list(passes_executed = 5L))
  )
  assign(harmonize_name, harmonize_dt, envir = isolated_env)

  summary_suffix <- build_postpro_iteration_summary(env = isolated_env)

  testthat::expect_identical(
    summary_suffix,
    " | cleans: 1 | harmonizatios: 5"
  )
})

testthat::test_that("run_pipeline_script emits compact non-duplicated failure summary", {
  root_dir <- build_temp_dir("whep-run-pipeline-script-error-")
  failing_script <- file.path(root_dir, "failing_pipeline_script.R")

  writeLines(
    c(
      "stop(\"Rule uniqueness validation failed for 'clean_footnotes.xlsx'.\\nrule file location: C:/rules/clean_footnotes.xlsx\\nrule rows=[396, 398]\", call. = FALSE)"
    ),
    con = failing_script
  )

  error_message <- tryCatch(
    {
      run_pipeline_script(failing_script)
      NA_character_
    },
    error = function(condition_value) {
      conditionMessage(condition_value)
    }
  )

  testthat::expect_match(
    error_message,
    "pipeline script execution failed",
    ignore.case = TRUE
  )
  testthat::expect_match(error_message, "script:", ignore.case = TRUE)
  testthat::expect_match(
    error_message,
    "cause:\\s*Rule uniqueness validation failed\\s*for\\s*'clean_footnotes\\.xlsx'\\."
  )
  testthat::expect_match(
    error_message,
    "location: C:/rules/clean_footnotes.xlsx",
    fixed = TRUE
  )
  testthat::expect_no_match(error_message, "details:", ignore.case = TRUE)
  testthat::expect_no_match(
    error_message,
    "Caused by error",
    ignore.case = TRUE
  )
})
