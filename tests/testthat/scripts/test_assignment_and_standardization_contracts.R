options(
  whep.run_postpro_pipeline.auto = FALSE,
  whep.run_pipeline.auto = FALSE
)

source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-assertions.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-time-formatting.R"),
  echo = FALSE
)
source(
  here::here(
    "r",
    "0-general_pipeline",
    "02-helpers",
    "02-string-normalization.R"
  ),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-numeric-coercion.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-token-extraction.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-data-table.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-export-validation.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-config-accessors.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-progress.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-sorting.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-environment.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-checkpoints.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-data-cleaning.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-io-cache.R"),
  echo = FALSE
)
source(
  here::here("r", "2-postpro_pipeline", "run_postpro_pipeline.R"),
  echo = FALSE
)
source(here::here("r", "run_pipeline.R"), echo = FALSE)

testthat::test_that("assign_environment_values assigns named values deterministically", {
  env <- new.env(parent = emptyenv())

  result <- assign_environment_values(
    values = list(alpha = 1L, beta = "b"),
    env = env
  )

  testthat::expect_true(isTRUE(invisible(result)))
  testthat::expect_identical(env$alpha, 1L)
  testthat::expect_identical(env$beta, "b")
})

testthat::test_that("assign_environment_values handles empty lists and overwrites existing bindings", {
  env <- new.env(parent = emptyenv())
  env$alpha <- 100L

  empty_result <- assign_environment_values(values = list(), env = env)
  overwrite_result <- assign_environment_values(
    values = list(alpha = 5L),
    env = env
  )

  testthat::expect_true(isTRUE(invisible(empty_result)))
  testthat::expect_true(isTRUE(invisible(overwrite_result)))
  testthat::expect_identical(env$alpha, 5L)
})

testthat::test_that("assign_environment_values errors on unnamed values", {
  env <- new.env(parent = emptyenv())

  testthat::expect_error(
    assign_environment_values(values = list(1L, 2L), env = env),
    "named|Must have names"
  )
})

testthat::test_that("validate_conversion_rules accepts normalize legacy schema", {
  legacy_rules <- data.table::data.table(
    commodity = c("wheat", "rice"),
    from_unit = c("kg", "kg"),
    to_unit = c("g", "g"),
    factor = c("1000", "1000"),
    offset = c("0", "0")
  )

  normalize_rules <- normalize_conversion_rule_columns(legacy_rules)

  testthat::expect_invisible(validate_conversion_rules(normalize_rules))
})

testthat::test_that("validate_conversion_rules errors on duplicated commodity_key/unit_source", {
  duplicate_rules <- data.table::data.table(
    commodity_key = c("wheat", "wheat"),
    unit_source = c("kg", "kg"),
    unit_target = c("g", "mg"),
    unit_factor = c(1000, 1000000),
    unit_offset = c(0, 0)
  )

  testthat::expect_error(
    validate_conversion_rules(duplicate_rules),
    "duplicate"
  )
})

testthat::test_that("apply_standardize_rules converts values and stabilizes output contract", {
  mapped_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg"),
    value = c("2", "3")
  )

  prepared_rules_dt <- prepare_standardize_rules(data.table::data.table(
    commodity_key = "wheat",
    unit_source = "kg",
    unit_target = "g",
    unit_factor = 1000,
    unit_offset = 0
  ))

  result <- apply_standardize_rules(
    mapped_dt = mapped_dt,
    prepared_rules_dt = prepared_rules_dt,
    unit_column = "unit",
    value_column = "value",
    commodity_column = "commodity"
  )

  testthat::expect_named(result, c("data", "matched_count", "unmatched_count"))
  testthat::expect_s3_class(result$data, "data.table")
  testthat::expect_identical(result$matched_count, 1L)
  testthat::expect_identical(result$unmatched_count, 1L)
  testthat::expect_identical(result$data$unit[[1]], "g")
  testthat::expect_equal(result$data$value[[1]], 2000)
  testthat::expect_equal(result$data$value[[2]], 3)
})

testthat::test_that("apply_standardize_rules zero-rule path is deterministic", {
  mapped_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", ""),
    value = c("2", "")
  )

  result <- apply_standardize_rules(
    mapped_dt = mapped_dt,
    prepared_rules_dt = data.table::data.table(),
    unit_column = "unit",
    value_column = "value",
    commodity_column = "commodity"
  )

  testthat::expect_identical(result$matched_count, 0L)
  testthat::expect_identical(result$unmatched_count, 1L)
  testthat::expect_true(is.na(result$data$value[[2]]))
})

testthat::test_that("apply_standardize_rules errors for non-numeric value payload", {
  mapped_dt <- data.table::data.table(
    commodity = "Wheat",
    unit = "kg",
    value = "not_numeric"
  )

  testthat::expect_error(
    apply_standardize_rules(
      mapped_dt = mapped_dt,
      prepared_rules_dt = data.table::data.table(),
      unit_column = "unit",
      value_column = "value",
      commodity_column = "commodity"
    ),
    "non-numeric"
  )
})

testthat::test_that("run_pipeline validates missing pipeline roots", {
  testthat::expect_error(
    run_pipeline(show_view = FALSE, pipeline_root = "this/path/does/not/exist"),
    "pipeline root does not exist"
  )
})
