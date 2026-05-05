# tests/1-import_pipeline/test-validate-log.R
# unit tests for R/1-import_pipeline/13-validate_log.R

source(here::here("tests", "test_helper.R"), echo = FALSE)
import_scripts <- c(
  "10-file_io/10-metadata.R",
  "10-file_io/10-discovery.R",
  "11-reading/11-read-utils.R",
  "11-reading/11-sheet-read.R",
  "11-reading/11-batching.R",
  "12-transform/12-transform-utils.R",
  "12-transform/12-reshape.R",
  "12-transform/12-processing.R",
  "13-output/13-validate.R"
)
purrr::walk(import_scripts, \(script_name) {
  source(here::here("r", "1-import_pipeline", script_name), echo = FALSE)
})


# --- validate_mandatory_fields_dt --------------------------------------------

testthat::test_that("validate_mandatory_fields_dt returns no errors for complete data", {
  dt <- build_sample_long_dt()
  config <- build_test_config()

  result <- validate_mandatory_fields_dt(dt, config)

  testthat::expect_true(is.list(result))
  testthat::expect_true("data" %in% names(result))
  testthat::expect_true("errors" %in% names(result))
  testthat::expect_equal(length(result$errors), 0L)
})

testthat::test_that("validate_mandatory_fields_dt creates missing columns", {
  dt <- data.table::data.table(
    commodity = "wheat",
    variable = "commodityion",
    unit = "tonnes",
    year = "2020",
    value = "100",
    document = "test.xlsx"
  )
  config <- build_test_config()

  result <- validate_mandatory_fields_dt(dt, config)

  # Missing columns (continent, country) should be created as NA
  testthat::expect_true("continent" %in% names(result$data))
  testthat::expect_true("country" %in% names(result$data))
})


testthat::test_that("validate_mandatory_fields_dt detects missing values with correct error format", {
  dt <- data.table::data.table(
    continent = c("Asia", "", NA_character_),
    country = c("Japan", "France", ""),
    commodity = c("wheat", "rice", "corn"),
    variable = c("commodityion", "trade", "yield"),
    document = c("doc.xlsx", "doc.xlsx", "doc.xlsx")
  )
  config <- build_test_config()

  result <- validate_mandatory_fields_dt(dt, config)

  testthat::expect_true(length(result$errors) > 0)
  testthat::expect_true(any(grepl("continent", result$errors)))
  testthat::expect_true(any(grepl("country", result$errors)))
  testthat::expect_true(all(grepl(
    "^missing mandatory value in document",
    result$errors
  )))
})

testthat::test_that("validate_mandatory_fields_dt adds document column when absent", {
  dt <- data.table::data.table(
    continent = c("Asia"),
    country = c("")
  )
  config <- build_test_config()

  result <- validate_mandatory_fields_dt(dt, config)

  testthat::expect_true("document" %in% names(result$data))
  testthat::expect_equal(result$data[["document"]][1], "unknown_document")
  testthat::expect_true(length(result$errors) > 0)
})

testthat::test_that("validate_mandatory_fields_dt does not add row_id to output", {
  dt <- build_sample_long_dt()
  config <- build_test_config()

  result <- validate_mandatory_fields_dt(dt, config)

  testthat::expect_false("row_id" %in% names(result$data))
})


# --- detect_duplicates_dt ---------------------------------------------------

testthat::test_that("detect_duplicates_dt finds duplicate rows", {
  dt <- data.table::data.table(
    commodity = c("wheat", "wheat"),
    variable = c("commodityion", "commodityion"),
    year = c("2020", "2020"),
    value = c("100", "100"),
    document = c("file1.xlsx", "file1.xlsx"),
    continent = c("Asia", "Asia"),
    country = c("Japan", "Japan"),
    unit = c("tonnes", "tonnes"),
    footnotes = c(NA_character_, NA_character_),
    yearbook = c("yb_2024", "yb_2024"),
    notes = c(NA_character_, NA_character_)
  )

  result <- detect_duplicates_dt(dt)

  testthat::expect_true(is.list(result))
  testthat::expect_true("data" %in% names(result))
})

testthat::test_that("detect_duplicates_dt returns clean result for unique rows", {
  dt <- build_sample_long_dt()

  result <- detect_duplicates_dt(dt)

  testthat::expect_true(is.list(result))
})


# --- validate_long_dt --------------------------------------------------------

testthat::test_that("validate_long_dt runs full validation", {
  dt <- build_sample_long_dt()
  config <- build_test_config()

  result <- validate_long_dt(dt, config)

  testthat::expect_true(is.list(result))
  testthat::expect_true("data" %in% names(result))
  testthat::expect_true("errors" %in% names(result))
})


# --- validate_year_values ----------------------------------------------------

testthat::test_that("validate_year_values returns no errors for valid single years", {
  dt <- data.table::data.table(
    year = c("2020", "2021", "1900"),
    value = c("100", "200", "300"),
    document = c("doc.xlsx", "doc.xlsx", "doc.xlsx")
  )

  result <- validate_year_values(dt)

  testthat::expect_true(is.list(result))
  testthat::expect_true("errors" %in% names(result))
  testthat::expect_true("data" %in% names(result))
  testthat::expect_equal(length(result$errors), 0L)
})

testthat::test_that("validate_year_values returns no errors for valid year ranges", {
  dt <- data.table::data.table(
    year = c("2020-2021", "2019-2022"),
    value = c("100", "200"),
    document = c("doc.xlsx", "doc.xlsx")
  )

  result <- validate_year_values(dt)

  testthat::expect_equal(length(result$errors), 0L)
})

testthat::test_that("validate_year_values flags year below 1900", {
  dt <- data.table::data.table(
    year = c("1800"),
    value = c("100"),
    document = c("doc.xlsx")
  )

  result <- validate_year_values(dt)

  testthat::expect_true(length(result$errors) > 0L)
  testthat::expect_true(any(grepl("1800", result$errors)))
  testthat::expect_true(any(grepl("plausible range", result$errors)))
})

testthat::test_that("validate_year_values flags year above current year + 1", {
  dt <- data.table::data.table(
    year = c("9999"),
    value = c("100"),
    document = c("doc.xlsx")
  )

  result <- validate_year_values(dt)

  testthat::expect_true(length(result$errors) > 0L)
  testthat::expect_true(any(grepl("9999", result$errors)))
})

testthat::test_that("validate_year_values flags inverted year range", {
  dt <- data.table::data.table(
    year = c("2025-2020"),
    value = c("100"),
    document = c("doc.xlsx")
  )

  result <- validate_year_values(dt)

  testthat::expect_true(length(result$errors) > 0L)
  testthat::expect_true(any(grepl("2025-2020", result$errors)))
  testthat::expect_true(any(grepl(
    "start year greater than end year",
    result$errors
  )))
})

testthat::test_that("validate_year_values flags year range outside plausible bounds", {
  dt <- data.table::data.table(
    year = c("1800-1850"),
    value = c("100"),
    document = c("doc.xlsx")
  )

  result <- validate_year_values(dt)

  testthat::expect_true(length(result$errors) > 0L)
  testthat::expect_true(any(grepl("plausible range", result$errors)))
})

testthat::test_that("validate_year_values skips NA and empty year values", {
  dt <- data.table::data.table(
    year = c(NA_character_, "", "2020"),
    value = c("100", "200", "300"),
    document = c("doc.xlsx", "doc.xlsx", "doc.xlsx")
  )

  result <- validate_year_values(dt)

  testthat::expect_equal(length(result$errors), 0L)
})

testthat::test_that("validate_year_values returns unchanged data", {
  dt <- data.table::data.table(
    year = c("2020", "1800"),
    value = c("100", "200"),
    document = c("doc.xlsx", "doc.xlsx")
  )

  result <- validate_year_values(dt)

  testthat::expect_equal(nrow(result$data), 2L)
})


# --- edge cases: empty input -------------------------------------------------

testthat::test_that("validate_long_dt handles empty data.table", {
  dt <- data.table::data.table(
    continent = character(0),
    country = character(0),
    commodity = character(0),
    variable = character(0),
    unit = character(0),
    year = character(0),
    value = character(0),
    notes = character(0),
    footnotes = character(0),
    yearbook = character(0),
    document = character(0)
  )
  config <- build_test_config()

  result <- validate_long_dt(dt, config)

  testthat::expect_true(is.list(result))
  testthat::expect_equal(nrow(result$data), 0L)
})
