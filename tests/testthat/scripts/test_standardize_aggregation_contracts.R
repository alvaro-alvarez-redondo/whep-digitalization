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

testthat::test_that("aggregate_standardized_rows sums duplicate groups deterministically", {
  input_dt <- data.table::data.table(
    commodity = c("wheat", "wheat", "rice"),
    unit = c("kg", "kg", "kg"),
    value = c(10, 20, 5)
  )

  result <- aggregate_standardized_rows(input_dt, value_column = "value")

  testthat::expect_s3_class(result, "data.table")
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_equal(result[commodity == "wheat", value], 30)
  testthat::expect_equal(result[commodity == "rice", value], 5)
})

testthat::test_that("extract_aggregated_rows returns only duplicate-group source rows", {
  input_dt <- data.table::data.table(
    commodity = c("wheat", "wheat", "rice"),
    unit = c("kg", "kg", "kg"),
    value = c(10, 20, 5)
  )

  result <- extract_aggregated_rows(input_dt, value_column = "value")

  testthat::expect_s3_class(result, "data.table")
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_true(all(result$commodity == "wheat"))
})

testthat::test_that("extract_aggregated_rows does not mutate input keys", {
  input_dt <- data.table::data.table(
    commodity = c("wheat", "wheat", "rice"),
    unit = c("kg", "kg", "kg"),
    value = c(10, 20, 5)
  )

  testthat::expect_null(data.table::key(input_dt))

  invisible(extract_aggregated_rows(input_dt, value_column = "value"))

  testthat::expect_null(data.table::key(input_dt))
})
