# tests/1-import_pipeline/test-transform.R
# unit tests for R/1-import_pipeline/12-transform.R

source(here::here("tests", "test_helper.R"), echo = FALSE)
import_scripts <- c(
  "10-file_io/10-metadata.R",
  "10-file_io/10-discovery.R",
  "11-reading/11-read-utils.R",
  "11-reading/11-sheet-read.R",
  "11-reading/11-batching.R",
  "12-transform/12-transform-utils.R",
  "12-transform/12-reshape.R",
  "12-transform/12-processing.R"
)
purrr::walk(import_scripts, \(script_name) {
  source(here::here("r", "1-import_pipeline", script_name), echo = FALSE)
})


# --- identify_year_columns ---------------------------------------------------

testthat::test_that("identify_year_columns detects yyyy columns", {
  df <- data.table::data.table(
    continent = "x",
    country = "y",
    `2020` = "1",
    `2021` = "2",
    value = "3"
  )
  config <- build_test_config()
  result <- identify_year_columns(df, config)

  testthat::expect_true("2020" %in% result)
  testthat::expect_true("2021" %in% result)
  testthat::expect_false("continent" %in% result)
})

testthat::test_that("identify_year_columns detects yyyy-yyyy range columns", {
  df <- data.table::data.table(`2020-2021` = "1", country = "x")
  config <- build_test_config()
  result <- identify_year_columns(df, config)

  testthat::expect_true("2020-2021" %in% result)
})

testthat::test_that("identify_year_columns returns empty for non-year columns", {
  df <- data.table::data.table(continent = "x", country = "y", value = "1")
  config <- build_test_config()
  result <- identify_year_columns(df, config)

  testthat::expect_equal(length(result), 0L)
})


# --- normalize_key_fields ----------------------------------------------------

testthat::test_that("normalize_key_fields adds missing base columns as NA", {
  dt <- data.table::data.table(
    commodity = c("wheat", "rice"),
    variable = c("commodityion", "trade")
  )
  config <- build_test_config()

  result <- normalize_key_fields(dt, "wheat", config)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_true("continent" %in% names(result))
  testthat::expect_true("country" %in% names(result))
})

testthat::test_that("normalize_key_fields normalizes hemisphere when present", {
  dt <- data.table::data.table(
    commodity = "wheat",
    variable = "commodityion",
    continent = "Asia",
    country = "Japan",
    hemisphere = "Northern Hemisphere"
  )
  config <- build_test_config()

  result <- normalize_key_fields(dt, "wheat", config)

  testthat::expect_true("hemisphere" %in% names(result))
  testthat::expect_equal(result$hemisphere, "northern hemisphere")
})

testthat::test_that("normalize_key_fields succeeds when hemisphere column is absent", {
  dt <- data.table::data.table(
    commodity = "wheat",
    variable = "commodityion",
    continent = "Asia",
    country = "Japan"
  )
  config <- build_test_config()

  result <- normalize_key_fields(dt, "wheat", config)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_false("hemisphere" %in% names(result))
})


# --- convert_year_columns ----------------------------------------------------

testthat::test_that("convert_year_columns sanitizes column names", {
  dt <- data.table::data.table(
    continent = "Asia",
    `2020` = "100",
    `2021` = "200"
  )
  config <- build_test_config()

  result <- convert_year_columns(dt, config)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_true(all(
    names(result) == make.names(names(result), unique = TRUE) |
      grepl("^\\d{4}", names(result))
  ))
})


# --- reshape_to_long ---------------------------------------------------------

testthat::test_that("reshape_to_long converts wide to long format", {
  dt <- data.table::data.table(
    continent = c("Asia", "Europe"),
    country = c("Japan", "France"),
    commodity = c("wheat", "rice"),
    variable = c("commodityion", "trade"),
    unit = c("tonnes", "tonnes"),
    footnotes = c(NA_character_, NA_character_),
    `2020` = c("100", "200"),
    `2021` = c("300", "400")
  )

  config <- build_test_config()
  result <- reshape_to_long(dt, config)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_true("year" %in% names(result))
  testthat::expect_true("value" %in% names(result))
  testthat::expect_equal(nrow(result), 4L) # 2 rows * 2 years
})

testthat::test_that("reshape_to_long preserves hemisphere column when present", {
  dt <- data.table::data.table(
    hemisphere = c("northern", "southern"),
    continent = c("Asia", "Europe"),
    country = c("Japan", "France"),
    commodity = c("wheat", "rice"),
    variable = c("commodityion", "trade"),
    unit = c("tonnes", "tonnes"),
    footnotes = c(NA_character_, NA_character_),
    `2020` = c("100", "200"),
    `2021` = c("300", "400")
  )

  config <- build_test_config()
  result <- reshape_to_long(dt, config)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_true("hemisphere" %in% names(result))
  testthat::expect_equal(
    sort(unique(result$hemisphere)),
    c("northern", "southern")
  )
  testthat::expect_equal(nrow(result), 4L)
})

testthat::test_that("reshape_to_long succeeds without hemisphere column", {
  dt <- data.table::data.table(
    continent = c("Asia", "Europe"),
    country = c("Japan", "France"),
    commodity = c("wheat", "rice"),
    variable = c("commodityion", "trade"),
    unit = c("tonnes", "tonnes"),
    footnotes = c(NA_character_, NA_character_),
    `2020` = c("100", "200")
  )

  config <- build_test_config()
  result <- reshape_to_long(dt, config)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_false("hemisphere" %in% names(result))
  testthat::expect_equal(nrow(result), 2L)
})


testthat::test_that("add_metadata appends document, notes, yearbook columns", {
  dt <- data.table::data.table(
    continent = "Asia",
    country = "Japan",
    year = "2020",
    value = "100"
  )

  config <- build_test_config()

  result <- add_metadata(
    dt,
    "whep_yb_2020_2021_a_b_wheat.xlsx",
    "yb_2020_2021",
    config
  )

  testthat::expect_true("document" %in% names(result))
  testthat::expect_true("yearbook" %in% names(result))
})


# --- build_empty_transform_result --------------------------------------------

testthat::test_that("build_empty_transform_result returns correct structure", {
  result <- build_empty_transform_result()

  testthat::expect_true(is.list(result))
  testthat::expect_true("wide_raw" %in% names(result))
  testthat::expect_true("long_raw" %in% names(result))
})


# --- assert_transform_result_contract ----------------------------------------

testthat::test_that("assert_transform_result_contract validates correct structure", {
  result <- list(
    wide_raw = data.table::data.table(a = 1),
    long_raw = data.table::data.table(b = 2)
  )

  testthat::expect_invisible(assert_transform_result_contract(result))
})

testthat::test_that("assert_transform_result_contract errors on missing keys", {
  result <- list(wide_raw = data.table::data.table(a = 1))

  testthat::expect_error(assert_transform_result_contract(result))
})


# --- edge cases: empty input -------------------------------------------------

testthat::test_that("identify_year_columns handles empty data frame", {
  df <- data.table::data.table()
  config <- build_test_config()
  result <- identify_year_columns(df, config)

  testthat::expect_equal(length(result), 0L)
})


# --- transform_files_list: early NA filtering --------------------------------

testthat::test_that("transform_files_list drops NA value rows before binding", {
  config <- build_test_config()

  file_list_dt <- data.table::data.table(
    file_name = c("file_a.xlsx", "file_b.xlsx"),
    yearbook = c("yb_2024", "yb_2024"),
    commodity = c("wheat", "rice")
  )

  wide_a <- data.table::data.table(
    commodity = "wheat",
    variable = "commodityion",
    unit = "tonnes",
    continent = "Asia",
    country = "Japan",
    footnotes = NA_character_,
    `2020` = "100",
    `2021` = NA_character_
  )
  wide_b <- data.table::data.table(
    commodity = "rice",
    variable = "trade",
    unit = "tonnes",
    continent = "Europe",
    country = "France",
    footnotes = NA_character_,
    `2020` = NA_character_,
    `2021` = "200"
  )
  read_data_list <- list(wide_a, wide_b)

  withr::with_options(list(whep.drop_na_values = TRUE), {
    result <- transform_files_list(file_list_dt, read_data_list, config)
    testthat::expect_true(all(!is.na(result$long_raw$value)))
    testthat::expect_equal(nrow(result$long_raw), 2L)
  })
})


# --- transform_file_dt: per-file NA filtering --------------------------------

testthat::test_that("transform_file_dt filters NA value rows from long output", {
  config <- build_test_config()

  wide_dt <- data.table::data.table(
    commodity = "wheat",
    variable = "commodityion",
    unit = "tonnes",
    continent = "Asia",
    country = "Japan",
    footnotes = NA_character_,
    `2020` = "100",
    `2021` = NA_character_
  )

  withr::with_options(list(whep.drop_na_values = TRUE), {
    result <- transform_file_dt(
      wide_dt,
      "test.xlsx",
      "yb_2024",
      "wheat",
      config
    )
    testthat::expect_true(all(!is.na(result$long_raw$value)))
    testthat::expect_equal(nrow(result$long_raw), 1L)
  })
})


# --- reshape_to_long: data.frame input ---------------------------------------

testthat::test_that("reshape_to_long converts data.frame input to data.table", {
  df <- data.frame(
    continent = c("Asia", "Europe"),
    country = c("Japan", "France"),
    commodity = c("wheat", "rice"),
    variable = c("commodityion", "trade"),
    unit = c("tonnes", "tonnes"),
    footnotes = c(NA_character_, NA_character_),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  df[["2020"]] <- c("100", "200")
  df[["2021"]] <- c("300", "400")

  config <- build_test_config()
  result <- reshape_to_long(df, config)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_equal(nrow(result), 4L)
})
