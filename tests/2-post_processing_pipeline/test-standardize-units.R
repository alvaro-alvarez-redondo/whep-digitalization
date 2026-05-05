# tests/2-postpro_pipeline/test-standardize-units.R
# unit tests for R/2-postpro_pipeline/24-standardize_units.R

source(here::here("tests", "test_helper.R"), echo = FALSE)
source(
  here::here("r", "2-postpro_pipeline", "run_postpro_pipeline.R"),
  echo = FALSE
)


write_standardize_workbook <- function(file_path, sheets_by_name) {
  wb <- openxlsx::createWorkbook()

  for (sheet_name in names(sheets_by_name)) {
    openxlsx::addWorksheet(wb, sheet_name)
    openxlsx::writeData(wb, sheet_name, sheets_by_name[[sheet_name]])
  }

  openxlsx::saveWorkbook(wb, file_path, overwrite = TRUE)
}


# --- standardize workbook ingestion ------------------------------------------

testthat::test_that("read_all_standardize_rule_files supports multi-sheet workbooks and excludes master_unit", {
  config <- build_test_config()

  workbook_path <- file.path(
    config$paths$data$import$standardization,
    "standardize_rules.xlsx"
  )

  write_standardize_workbook(
    workbook_path,
    list(
      standardize_unit = data.frame(
        commodity_key = "wheat",
        unit_source = "kg",
        unit_target = "g",
        unit_factor = 1000,
        unit_offset = 0
      ),
      master_unit = data.frame(
        commodity_key = "wheat",
        unit_source = "kg",
        unit_target = "g",
        unit_factor = 999,
        unit_offset = 0
      )
    )
  )

  payload <- read_all_standardize_rule_files(config)

  testthat::expect_equal(length(payload$source_paths), 1L)
  testthat::expect_equal(nrow(payload$rules), 1L)
  testthat::expect_identical(
    payload$rules$source_rule_sheet[[1]],
    "standardize_unit"
  )
  testthat::expect_equal(payload$rules$unit_factor[[1]], 1000)
})

testthat::test_that("read_all_standardize_rule_files reads all non-excluded matching sheets", {
  config <- build_test_config()

  workbook_path <- file.path(
    config$paths$data$import$standardization,
    "standardize_rules_multi.xlsx"
  )

  write_standardize_workbook(
    workbook_path,
    list(
      standardize_unit = data.frame(
        commodity_key = "wheat",
        unit_source = "kg",
        unit_target = "g",
        unit_factor = 1000,
        unit_offset = 0
      ),
      secondary_rules = data.frame(
        commodity_key = "rice",
        unit_source = "tonnes",
        unit_target = "kg",
        unit_factor = 1000,
        unit_offset = 0
      ),
      master_unit = data.frame(
        commodity_key = "rice",
        unit_source = "tonnes",
        unit_target = "kg",
        unit_factor = 1,
        unit_offset = 0
      ),
      notes = data.frame(note = "helper sheet")
    )
  )

  payload <- read_all_standardize_rule_files(config)

  testthat::expect_equal(nrow(payload$rules), 2L)
  testthat::expect_setequal(
    payload$rules$source_rule_sheet,
    c("standardize_unit", "secondary_rules")
  )
})


# --- validate_rule_schema ----------------------------------------------------

testthat::test_that("validate_rule_schema accepts complete schema", {
  rule_dt <- data.table::data.table(
    commodity_key = "wheat",
    unit_source = "kg",
    unit_target = "g",
    unit_factor = 1000,
    unit_offset = 0
  )

  required <- c(
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset"
  )

  testthat::expect_invisible(validate_rule_schema(rule_dt, required, "test"))
})

testthat::test_that("validate_rule_schema errors on missing columns", {
  rule_dt <- data.table::data.table(commodity_key = "wheat")

  testthat::expect_error(
    validate_rule_schema(rule_dt, c("commodity_key", "missing_col"), "test"),
    "Missing required columns"
  )
})

testthat::test_that("validate_rule_schema errors on NA in required columns", {
  rule_dt <- data.table::data.table(
    commodity_key = NA_character_,
    unit_source = "kg"
  )

  testthat::expect_error(
    validate_rule_schema(rule_dt, c("commodity_key", "unit_source"), "test"),
    "missing values"
  )
})


# --- normalize_conversion_rule_columns ---------------------------------------

testthat::test_that("normalize_conversion_rule_columns renames legacy columns", {
  legacy_dt <- data.table::data.table(
    commodity = "wheat",
    from_unit = "kg",
    to_unit = "g",
    factor = 1000,
    offset = 0
  )

  result <- normalize_conversion_rule_columns(legacy_dt)

  testthat::expect_true("commodity_key" %in% names(result))
  testthat::expect_true("unit_source" %in% names(result))
  testthat::expect_true("unit_target" %in% names(result))
  testthat::expect_true("unit_factor" %in% names(result))
  testthat::expect_true("unit_offset" %in% names(result))
})

testthat::test_that("normalize_conversion_rule_columns preserves modern column names", {
  modern_dt <- data.table::data.table(
    commodity_key = "wheat",
    unit_source = "kg",
    unit_target = "g",
    unit_factor = 1000,
    unit_offset = 0
  )

  result <- normalize_conversion_rule_columns(modern_dt)

  testthat::expect_true("unit_source" %in% names(result))
  testthat::expect_true("unit_factor" %in% names(result))
})


# --- validate_conversion_rules -----------------------------------------------

testthat::test_that("validate_conversion_rules accepts valid rules", {
  rules_dt <- data.table::data.table(
    commodity_key = c("wheat", "rice"),
    unit_source = c("kg", "kg"),
    unit_target = c("g", "g"),
    unit_factor = c(1000, 1000),
    unit_offset = c(0, 0)
  )

  testthat::expect_invisible(validate_conversion_rules(rules_dt))
})

testthat::test_that("validate_conversion_rules errors on duplicated commodity_key/unit_source", {
  rules_dt <- data.table::data.table(
    commodity_key = c("wheat", "wheat"),
    unit_source = c("kg", "kg"),
    unit_target = c("g", "mg"),
    unit_factor = c(1000, 1000000),
    unit_offset = c(0, 0)
  )

  testthat::expect_error(validate_conversion_rules(rules_dt), "duplicate")
})

testthat::test_that("validate_conversion_rules detects chained conversions", {
  rules_dt <- data.table::data.table(
    commodity_key = c("wheat", "wheat"),
    unit_source = c("kg", "g"),
    unit_target = c("g", "mg"),
    unit_factor = c(1000, 1000),
    unit_offset = c(0, 0)
  )

  testthat::expect_error(validate_conversion_rules(rules_dt), "chained")
})

testthat::test_that("validate_conversion_rules errors on non-finite unit_factor", {
  rules_dt <- data.table::data.table(
    commodity_key = "wheat",
    unit_source = "kg",
    unit_target = "g",
    unit_factor = Inf,
    unit_offset = 0
  )

  testthat::expect_error(validate_conversion_rules(rules_dt), "finite")
})


# --- prepare_standardize_rules -----------------------------------------------

testthat::test_that("prepare_standardize_rules materializes numeric columns and keys", {
  raw_dt <- data.table::data.table(
    commodity_key = "wheat",
    unit_source = "kg",
    unit_target = "g",
    unit_factor = 1000,
    unit_offset = 0
  )

  result <- prepare_standardize_rules(raw_dt)

  testthat::expect_true("unit_factor_num" %in% names(result))
  testthat::expect_true("unit_offset_num" %in% names(result))
  testthat::expect_true("commodity_match_key" %in% names(result))
  testthat::expect_true("unit_source_key" %in% names(result))
})

testthat::test_that("prepare_standardize_rules handles empty input", {
  result <- prepare_standardize_rules(data.table::data.table())

  testthat::expect_equal(nrow(result), 0L)
})


# --- apply_standardize_rules ------------------------------------------------

testthat::test_that("apply_standardize_rules converts values", {
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

  testthat::expect_named(
    result,
    c("data", "matched_count", "unmatched_count", "matched_rule_counts")
  )
  testthat::expect_s3_class(result$data, "data.table")
  testthat::expect_identical(result$matched_count, 1L)
  testthat::expect_identical(result$unmatched_count, 1L)
  testthat::expect_true(data.table::is.data.table(result$matched_rule_counts))
  testthat::expect_identical(result$matched_rule_counts$affected_rows[[1]], 1L)
  testthat::expect_identical(result$data$unit[[1]], "g")
  testthat::expect_equal(result$data$value[[1]], 2000)
})

testthat::test_that("apply_standardize_rules with unit_offset applies conversion offset", {
  mapped_dt <- data.table::data.table(
    commodity = "temp_sensor",
    unit = "celsius",
    value = "100"
  )

  prepared_rules_dt <- prepare_standardize_rules(data.table::data.table(
    commodity_key = "temp_sensor",
    unit_source = "celsius",
    unit_target = "fahrenheit",
    unit_factor = 1.8,
    unit_offset = 32
  ))

  result <- apply_standardize_rules(
    mapped_dt = mapped_dt,
    prepared_rules_dt = prepared_rules_dt,
    unit_column = "unit",
    value_column = "value",
    commodity_column = "commodity"
  )

  testthat::expect_equal(result$data$value[[1]], 212)
  testthat::expect_equal(result$data$unit[[1]], "fahrenheit")
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

testthat::test_that("apply_standardize_rules errors for non-numeric values", {
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

testthat::test_that("apply_standardize_rules uses 'all commodity' fallback for unmatched commodity", {
  mapped_dt <- data.table::data.table(
    commodity = c("Wheat", "Corn", "Rice"),
    unit = c("kg", "kg", "kg"),
    value = c("2", "3", "5")
  )

  prepared_rules_dt <- prepare_standardize_rules(data.table::data.table(
    commodity_key = c("wheat", "all commodity"),
    unit_source = c("kg", "kg"),
    unit_target = c("g", "g"),
    unit_factor = c(1000, 1000),
    unit_offset = c(0, 0)
  ))

  result <- apply_standardize_rules(
    mapped_dt = mapped_dt,
    prepared_rules_dt = prepared_rules_dt,
    unit_column = "unit",
    value_column = "value",
    commodity_column = "commodity"
  )

  testthat::expect_identical(result$matched_count, 3L)
  testthat::expect_identical(result$unmatched_count, 0L)
  testthat::expect_equal(result$data$value[[1]], 2000)
  testthat::expect_equal(result$data$value[[2]], 3000)
  testthat::expect_equal(result$data$value[[3]], 5000)
})

testthat::test_that("apply_standardize_rules attributes fallback matches to all-commodity rule keys", {
  mapped_dt <- data.table::data.table(
    commodity = c("Wheat", "Corn", "Rice"),
    unit = c("kg", "kg", "kg"),
    value = c("2", "3", "5")
  )

  prepared_rules_dt <- prepare_standardize_rules(data.table::data.table(
    commodity_key = c("wheat", "all commodity"),
    unit_source = c("kg", "kg"),
    unit_target = c("g", "g"),
    unit_factor = c(1000, 1000),
    unit_offset = c(0, 0)
  ))

  result <- apply_standardize_rules(
    mapped_dt = mapped_dt,
    prepared_rules_dt = prepared_rules_dt,
    unit_column = "unit",
    value_column = "value",
    commodity_column = "commodity"
  )

  keyed_counts <- result$matched_rule_counts[order(
    rule_commodity_match_key,
    applied_commodity_match_key
  )]

  testthat::expect_equal(nrow(keyed_counts), 3L)
  testthat::expect_identical(
    keyed_counts$rule_commodity_match_key,
    c("all commodity", "all commodity", "wheat")
  )
  testthat::expect_identical(
    keyed_counts$applied_commodity_match_key,
    c("corn", "rice", "wheat")
  )
  testthat::expect_identical(keyed_counts$affected_rows, c(1L, 1L, 1L))
})

testthat::test_that("apply_standardize_rules prioritizes specific commodity rules over 'all commodity'", {
  mapped_dt <- data.table::data.table(
    commodity = c("egg", "milk", "wheat"),
    unit = c("1000 egg", "hectoliter", "kg"),
    value = c("2", "10", "5")
  )

  prepared_rules_dt <- prepare_standardize_rules(data.table::data.table(
    commodity_key = c("egg", "all commodity", "all commodity"),
    unit_source = c("1000 egg", "1000 egg", "kg"),
    unit_target = c("tonne", "tonne", "g"),
    unit_factor = c(0.0539, 0.001, 1000),
    unit_offset = c(0, 0, 0)
  ))

  result <- apply_standardize_rules(
    mapped_dt = mapped_dt,
    prepared_rules_dt = prepared_rules_dt,
    unit_column = "unit",
    value_column = "value",
    commodity_column = "commodity"
  )

  testthat::expect_identical(result$matched_count, 2L)
  testthat::expect_equal(result$data$value[[1]], 2 * 0.0539)
  testthat::expect_equal(result$data$unit[[1]], "tonne")
  testthat::expect_equal(result$data$value[[3]], 5000)
  testthat::expect_equal(result$data$unit[[3]], "g")
})

testthat::test_that("apply_standardize_rules 'all commodity' fallback with mixed specificity", {
  mapped_dt <- data.table::data.table(
    commodity = c("coconut", "egg", "rice", "wheat"),
    unit = c("count", "1000 egg", "kg", "kg"),
    value = c("1000", "100", "500", "2000")
  )

  prepared_rules_dt <- prepare_standardize_rules(data.table::data.table(
    commodity_key = c("coconut", "egg", "all commodity", "all commodity"),
    unit_source = c("count", "1000 egg", "kg", "tonne"),
    unit_target = c("tonne", "tonne", "g", "kg"),
    unit_factor = c(0.001, 0.0539, 1000, 1000),
    unit_offset = c(0, 0, 0, 0)
  ))

  result <- apply_standardize_rules(
    mapped_dt = mapped_dt,
    prepared_rules_dt = prepared_rules_dt,
    unit_column = "unit",
    value_column = "value",
    commodity_column = "commodity"
  )

  testthat::expect_identical(result$matched_count, 4L)
  testthat::expect_equal(result$data$value[[1]], 1)
  testthat::expect_equal(result$data$value[[2]], 100 * 0.0539)
  testthat::expect_equal(result$data$value[[3]], 500000)
  testthat::expect_equal(result$data$value[[4]], 2000000)
})

testthat::test_that("validate_conversion_rules allows chained rules when one is 'all commodity'", {
  rules_dt <- data.table::data.table(
    commodity_key = c("all commodity", "all commodity", "wheat"),
    unit_source = c("kg", "g", "kg"),
    unit_target = c("g", "mg", "g"),
    unit_factor = c(1000, 1000, 1000),
    unit_offset = c(0, 0, 0)
  )

  testthat::expect_invisible(validate_conversion_rules(rules_dt))
})

testthat::test_that("validate_conversion_rules detects chained specific-commodity rules excluding 'all commodity'", {
  rules_dt <- data.table::data.table(
    commodity_key = c("wheat", "wheat", "all commodity"),
    unit_source = c("kg", "g", "kg"),
    unit_target = c("g", "mg", "g"),
    unit_factor = c(1000, 1000, 1000),
    unit_offset = c(0, 0, 0)
  )

  testthat::expect_error(validate_conversion_rules(rules_dt), "chained")
})


# --- build_standardize_layer_audit ------------------------------------------

testthat::test_that("build_standardize_layer_audit mirrors standardize workbook schema", {
  layer_rules_dt <- prepare_standardize_rules(data.table::data.table(
    commodity_key = c("wheat", "all commodity"),
    unit_source = c("kg", "kg"),
    unit_target = c("g", "g"),
    unit_factor = c(1000, 1000),
    unit_offset = c(0, 0),
    source_rule_sheet = c("standardize_unit", "standardize_unit"),
    source_rule_file = c(
      "standardize_units_rules.xlsx",
      "standardize_units_rules.xlsx"
    )
  ))

  matched_rule_counts_dt <- data.table::data.table(
    rule_commodity_match_key = c("wheat", "all commodity", "all commodity"),
    applied_commodity_match_key = c("wheat", "corn", "rice"),
    unit_source_key = c("kg", "kg", "kg"),
    affected_rows = c(1L, 1L, 1L)
  )

  result <- build_standardize_layer_audit(
    layer_rules_dt = layer_rules_dt,
    matched_rule_counts_dt = matched_rule_counts_dt,
    source_paths = "standardize_units_rules.xlsx"
  )

  expected_columns <- c(
    "affected_rows",
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset"
  )

  testthat::expect_identical(names(result), expected_columns)
  testthat::expect_equal(nrow(result), 3L)
  testthat::expect_setequal(result$commodity_key, c("wheat", "corn", "rice"))

  all_commodity_rows <- result[commodity_key %in% c("corn", "rice")]
  testthat::expect_equal(nrow(all_commodity_rows), 2L)
  testthat::expect_true(all(all_commodity_rows$affected_rows == 1L))
  testthat::expect_true(all(all_commodity_rows$unit_factor == 1000))
  testthat::expect_true(all(all_commodity_rows$unit_offset == 0))
})


# --- aggregate_standardized_rows ---------------------------------------------

testthat::test_that("aggregate_standardized_rows sums duplicate groups", {
  dt <- data.table::data.table(
    commodity = c("wheat", "wheat", "rice"),
    unit = c("kg", "kg", "kg"),
    value = c(10, 20, 5)
  )

  result <- aggregate_standardized_rows(dt, "value")

  testthat::expect_s3_class(result, "data.table")
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_equal(
    result[commodity == "wheat"]$value,
    30
  )
  testthat::expect_equal(
    result[commodity == "rice"]$value,
    5
  )
})

testthat::test_that("aggregate_standardized_rows returns empty table unchanged", {
  dt <- data.table::data.table(
    commodity = character(0),
    unit = character(0),
    value = numeric(0)
  )

  result <- aggregate_standardized_rows(dt, "value")

  testthat::expect_equal(nrow(result), 0L)
  testthat::expect_identical(names(result), c("commodity", "unit", "value"))
})

testthat::test_that("aggregate_standardized_rows is idempotent", {
  dt <- data.table::data.table(
    commodity = c("wheat", "rice"),
    unit = c("kg", "kg"),
    value = c(10, 5)
  )

  result1 <- aggregate_standardized_rows(dt, "value")
  result2 <- aggregate_standardized_rows(result1, "value")

  testthat::expect_identical(result1, result2)
})

testthat::test_that("aggregate_standardized_rows handles all-NA group", {
  dt <- data.table::data.table(
    commodity = c("wheat", "wheat"),
    unit = c("kg", "kg"),
    value = c(NA_real_, NA_real_)
  )

  result <- aggregate_standardized_rows(dt, "value")

  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_true(is.na(result$value))
})

testthat::test_that("aggregate_standardized_rows sums non-NA with partial NA", {
  dt <- data.table::data.table(
    commodity = c("wheat", "wheat"),
    unit = c("kg", "kg"),
    value = c(10, NA_real_)
  )

  result <- aggregate_standardized_rows(dt, "value")

  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_equal(result$value, 10)
})

testthat::test_that("aggregate_standardized_rows preserves column order", {
  dt <- data.table::data.table(
    commodity = c("wheat", "wheat"),
    value = c(10, 20),
    unit = c("kg", "kg")
  )

  result <- aggregate_standardized_rows(dt, "value")

  testthat::expect_identical(names(result), c("commodity", "value", "unit"))
})

testthat::test_that("aggregate_standardized_rows skips already-unique data", {
  dt <- data.table::data.table(
    commodity = c("wheat", "rice"),
    unit = c("kg", "kg"),
    value = c(10, 5)
  )

  result <- aggregate_standardized_rows(dt, "value")

  testthat::expect_identical(result, dt)
})

testthat::test_that("aggregate_standardized_rows returns single row unchanged", {
  dt <- data.table::data.table(
    commodity = "wheat",
    unit = "kg",
    value = 42
  )

  result <- aggregate_standardized_rows(dt, "value")

  testthat::expect_identical(result, dt)
})

testthat::test_that("aggregate_standardized_rows handles only-value-column edge case", {
  dt <- data.table::data.table(value = c(10, 20, 30))

  result <- aggregate_standardized_rows(dt, "value")

  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_equal(result$value, 60)
})

testthat::test_that("aggregate_standardized_rows errors on missing value column", {
  dt <- data.table::data.table(commodity = "wheat", unit = "kg")

  testthat::expect_error(
    aggregate_standardized_rows(dt, "value"),
    "not found"
  )
})

testthat::test_that("aggregate_standardized_rows handles mixed column types", {
  dt <- data.table::data.table(
    commodity = c("wheat", "wheat"),
    year = as.Date(c("2020-01-01", "2020-01-01")),
    category = factor(c("a", "a")),
    value = c(10, 20)
  )

  result <- aggregate_standardized_rows(dt, "value")

  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_equal(result$value, 30)
  testthat::expect_s3_class(result$year, "Date")
  testthat::expect_s3_class(result$category, "factor")
})


# --- extract_aggregated_rows -------------------------------------------------

testthat::test_that("extract_aggregated_rows returns only rows from duplicate groups", {
  dt <- data.table::data.table(
    commodity = c("wheat", "wheat", "rice"),
    unit = c("kg", "kg", "kg"),
    value = c(10, 20, 5)
  )

  result <- extract_aggregated_rows(dt, "value")

  testthat::expect_s3_class(result, "data.table")
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_true(all(result$commodity == "wheat"))
})

testthat::test_that("extract_aggregated_rows returns empty table when no duplicates", {
  dt <- data.table::data.table(
    commodity = c("wheat", "rice"),
    unit = c("kg", "kg"),
    value = c(10, 5)
  )

  result <- extract_aggregated_rows(dt, "value")

  testthat::expect_equal(nrow(result), 0L)
  testthat::expect_identical(names(result), c("commodity", "unit", "value"))
})

testthat::test_that("extract_aggregated_rows returns empty table for empty input", {
  dt <- data.table::data.table(
    commodity = character(0),
    unit = character(0),
    value = numeric(0)
  )

  result <- extract_aggregated_rows(dt, "value")

  testthat::expect_equal(nrow(result), 0L)
})

testthat::test_that("extract_aggregated_rows preserves column order", {
  dt <- data.table::data.table(
    commodity = c("wheat", "wheat"),
    value = c(10, 20),
    unit = c("kg", "kg")
  )

  result <- extract_aggregated_rows(dt, "value")

  testthat::expect_identical(names(result), c("commodity", "value", "unit"))
})


# --- attach_standardize_diagnostics aggregation fields -----------------------

testthat::test_that("attach_standardize_diagnostics includes aggregation fields", {
  dt <- data.table::data.table(commodity = "wheat", value = 10)

  result <- attach_standardize_diagnostics(
    standardized_dt = dt,
    clean_rows_count = 5L,
    matched_count = 3L,
    unmatched_count = 2L,
    rules_count = 1L,
    rule_sources = "test.xlsx",
    aggregation_enabled = TRUE,
    rows_before_aggregation = 5L,
    rows_after_aggregation = 3L
  )

  diag <- attr(result, "layer_diagnostics")$standardize_units

  testthat::expect_true(diag$aggregation_enabled)
  testthat::expect_identical(diag$rows_before_aggregation, 5L)
  testthat::expect_identical(diag$rows_after_aggregation, 3L)
  testthat::expect_identical(diag$collapsed_rows_count, 2L)
  testthat::expect_identical(diag$aggregated_groups_count, 3L)
})

testthat::test_that("attach_standardize_diagnostics omits aggregation counts when disabled", {
  dt <- data.table::data.table(commodity = "wheat", value = 10)

  result <- attach_standardize_diagnostics(
    standardized_dt = dt,
    clean_rows_count = 1L,
    matched_count = 1L,
    unmatched_count = 0L,
    rules_count = 1L,
    rule_sources = "test.xlsx",
    aggregation_enabled = FALSE
  )

  diag <- attr(result, "layer_diagnostics")$standardize_units

  testthat::expect_false(diag$aggregation_enabled)
  testthat::expect_null(diag$rows_before_aggregation)
})
