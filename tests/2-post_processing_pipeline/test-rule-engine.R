# tests/2-postpro_pipeline/test-rule-engine.R
# unit tests for R/2-postpro_pipeline/23-postpro_rule_engine.R

source(here::here("tests", "test_helper.R"), echo = FALSE)
source(
  here::here("r", "2-postpro_pipeline", "run_postpro_pipeline.R"),
  echo = FALSE
)


# --- coerce_rule_schema ------------------------------------------------------

testthat::test_that("coerce_rule_schema normalizes stage-prefixed columns", {
  raw_rule_dt <- data.frame(
    clean_column_source = "commodity",
    clean_value_source_raw = "Wheat",
    clean_column_target = "unit",
    clean_value_target_raw = "kg",
    clean_value_target = "kilogram",
    stringsAsFactors = FALSE
  )

  result <- coerce_rule_schema(
    rule_dt = raw_rule_dt,
    stage_name = "clean",
    rule_file_id = "test.xlsx"
  )

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_true("column_source" %in% names(result))
  testthat::expect_true("value_target" %in% names(result))
  testthat::expect_equal(result$value_target[[1]], "kilogram")
})

testthat::test_that("coerce_rule_schema errors on missing required columns", {
  raw_rule_dt <- data.frame(
    column_source = "commodity",
    stringsAsFactors = FALSE
  )

  error_message <- tryCatch(
    {
      coerce_rule_schema(
        rule_dt = raw_rule_dt,
        stage_name = "clean",
        rule_file_id = "test.xlsx",
        rule_file_path = "C:/rules/test.xlsx"
      )

      NA_character_
    },
    error = function(condition_value) {
      conditionMessage(condition_value)
    }
  )

  testthat::expect_match(error_message, "(?i)missing\\s+required\\s+columns")
  testthat::expect_match(
    error_message,
    "rule file location",
    ignore.case = TRUE
  )
  testthat::expect_match(error_message, "C:/rules/test.xlsx", fixed = TRUE)
  testthat::expect_match(error_message, "stage: clean", fixed = TRUE)
})

testthat::test_that("coerce_rule_schema errors on duplicate columns after normalization", {
  raw_rule_dt <- data.frame(
    clean_column_source = "commodity",
    column_source = "commodity",
    clean_value_source_raw = "Wheat",
    clean_column_target = "unit",
    clean_value_target_raw = "kg",
    clean_value_target = "kilogram",
    stringsAsFactors = FALSE
  )

  testthat::expect_error(
    coerce_rule_schema(
      rule_dt = raw_rule_dt,
      stage_name = "clean",
      rule_file_id = "test.xlsx"
    ),
    "(?i)duplicate\\s+columns"
  )
})


# --- ensure_rule_referenced_columns ------------------------------------------

testthat::test_that("ensure_rule_referenced_columns adds missing columns to dataset", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg")
  )

  rules_dt <- data.table::data.table(
    column_source = "commodity",
    column_target = "new_column"
  )

  result <- ensure_rule_referenced_columns(dataset_dt, rules_dt)

  testthat::expect_true("new_column" %in% names(result))
  testthat::expect_true(all(is.na(result$new_column)))
})

testthat::test_that("ensure_rule_referenced_columns preserves existing columns", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg")
  )

  rules_dt <- data.table::data.table(
    column_source = "commodity",
    column_target = "unit"
  )

  result <- ensure_rule_referenced_columns(dataset_dt, rules_dt)

  testthat::expect_identical(result$unit, c("kg", "kg"))
})


# --- validate_canonical_rules ------------------------------------------------

testthat::test_that("validate_canonical_rules allows NA in value columns for clean stage", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg")
  )

  rules_dt <- data.table::data.table(
    column_source = c("commodity", "commodity"),
    value_source_raw = c(NA_character_, "Rice"),
    value_source = c(NA_character_, NA_character_),
    column_target = c("unit", "unit"),
    value_target_raw = c(NA_character_, "kg"),
    value_target = c(NA_character_, "kilogram")
  )

  testthat::expect_invisible(
    validate_canonical_rules(
      rules_dt = rules_dt,
      dataset_dt = dataset_dt,
      rule_file_id = "test.xlsx",
      stage_name = "clean"
    )
  )
})

testthat::test_that("validate_canonical_rules fails for NA in structural columns", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat"),
    unit = c("kg")
  )

  rules_dt <- data.table::data.table(
    column_source = NA_character_,
    value_source_raw = NA_character_,
    value_source = NA_character_,
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram"
  )

  error_message <- tryCatch(
    {
      validate_canonical_rules(
        rules_dt = rules_dt,
        dataset_dt = dataset_dt,
        rule_file_id = "test.xlsx",
        rule_file_path = "C:/rules/test.xlsx",
        stage_name = "clean"
      )

      NA_character_
    },
    error = function(condition_value) {
      conditionMessage(condition_value)
    }
  )

  testthat::expect_match(
    error_message,
    "(?i)missing\\s+values\\s+in\\s+required\\s+columns"
  )
  testthat::expect_match(
    error_message,
    "rule file location",
    ignore.case = TRUE
  )
  testthat::expect_match(error_message, "stage: clean", fixed = TRUE)
  testthat::expect_match(
    error_message,
    "rule rows with missing required values",
    ignore.case = TRUE
  )
})

testthat::test_that("validate_canonical_rules reports missing dataset columns with row context", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat"),
    unit = c("kg")
  )

  rules_dt <- data.table::data.table(
    column_source = "missing_source_column",
    value_source_raw = "Wheat",
    value_source = "Wheat",
    column_target = "missing_target_column",
    value_target_raw = "kg",
    value_target = "kilogram"
  )

  error_message <- tryCatch(
    {
      validate_canonical_rules(
        rules_dt = rules_dt,
        dataset_dt = dataset_dt,
        rule_file_id = "clean_missing_columns.xlsx",
        rule_file_path = "C:/rules/clean_missing_columns.xlsx",
        stage_name = "clean"
      )

      NA_character_
    },
    error = function(condition_value) {
      conditionMessage(condition_value)
    }
  )

  testthat::expect_match(
    error_message,
    "Rule columns are not present in dataset",
    ignore.case = TRUE
  )
  testthat::expect_match(
    error_message,
    "missing source columns in dataset",
    ignore.case = TRUE
  )
  testthat::expect_match(
    error_message,
    "missing target columns in dataset",
    ignore.case = TRUE
  )
  testthat::expect_match(
    error_message,
    "rule rows referencing missing dataset columns",
    ignore.case = TRUE
  )
  testthat::expect_match(
    error_message,
    "C:/rules/clean_missing_columns.xlsx",
    fixed = TRUE
  )
})

testthat::test_that("validate_canonical_rules reports type-compatibility violations with row previews", {
  dataset_dt <- data.table::data.table(
    amount = as.numeric(1),
    unit = "kg"
  )

  rules_dt <- data.table::data.table(
    column_source = "amount",
    value_source_raw = "not_numeric",
    value_source = NA_character_,
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram"
  )

  error_message <- tryCatch(
    {
      validate_canonical_rules(
        rules_dt = rules_dt,
        dataset_dt = dataset_dt,
        rule_file_id = "clean_type_cast.xlsx",
        rule_file_path = "C:/rules/clean_type_cast.xlsx",
        stage_name = "clean"
      )

      NA_character_
    },
    error = function(condition_value) {
      conditionMessage(condition_value)
    }
  )

  testthat::expect_match(
    error_message,
    "Type compatibility validation failed",
    ignore.case = TRUE
  )
  testthat::expect_match(
    error_message,
    "expected type:\\s*numeric",
    ignore.case = TRUE
  )
  testthat::expect_match(
    error_message,
    "invalid rule values (preview)",
    fixed = TRUE
  )
  testthat::expect_match(
    error_message,
    "rule rows with invalid values",
    ignore.case = TRUE
  )
  testthat::expect_match(
    error_message,
    "C:/rules/clean_type_cast.xlsx",
    fixed = TRUE
  )
})

testthat::test_that("validate_canonical_rules detects duplicate rule keys", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    unit = "kg"
  )

  rules_dt <- data.table::data.table(
    column_source = c("commodity", "commodity"),
    value_source_raw = c("Wheat", "Wheat"),
    column_target = c("unit", "unit"),
    value_target_raw = c("kg", "kg"),
    value_target = c("kilogram", "gram")
  )

  testthat::expect_error(
    validate_canonical_rules(
      rules_dt = rules_dt,
      dataset_dt = dataset_dt,
      rule_file_id = "test.xlsx",
      stage_name = "clean"
    )
  )
})

testthat::test_that("validate_canonical_rules allows source rewrites that branch by value_target_raw", {
  dataset_dt <- data.table::data.table(
    commodity = "wine",
    variable = "area"
  )

  rules_dt <- data.table::data.table(
    column_source = c("commodity", "commodity"),
    value_source_raw = c("wine", "wine"),
    value_source = c("vineyards: wine", "wine"),
    column_target = c("variable", "variable"),
    value_target_raw = c("area", "commodityion"),
    value_target = c("area", "commodityion")
  )

  testthat::expect_invisible(
    validate_canonical_rules(
      rules_dt = rules_dt,
      dataset_dt = dataset_dt,
      rule_file_id = "test.xlsx",
      stage_name = "clean"
    )
  )
})

testthat::test_that("validate_canonical_rules rejects duplicated conditional keys even if source rewrites differ", {
  dataset_dt <- data.table::data.table(
    commodity = "wine",
    variable = "area"
  )

  rules_dt <- data.table::data.table(
    column_source = c("commodity", "commodity"),
    value_source_raw = c("wine", "wine"),
    value_source = c("vineyards: wine", "wine"),
    column_target = c("variable", "variable"),
    value_target_raw = c("area", "area"),
    value_target = c("area", "area")
  )

  testthat::expect_error(
    validate_canonical_rules(
      rules_dt = rules_dt,
      dataset_dt = dataset_dt,
      rule_file_id = "test.xlsx",
      stage_name = "clean"
    ),
    "Rule uniqueness validation failed"
  )
})

testthat::test_that("validate_canonical_rules reports duplicate key location and row previews", {
  dataset_dt <- data.table::data.table(
    commodity = "wine",
    variable = "area"
  )

  rules_dt <- data.table::data.table(
    column_source = c("commodity", "commodity", "commodity"),
    value_source_raw = c("wine", "wine", "wine"),
    value_source = c("wine", "wine", "wine"),
    column_target = c("variable", "variable", "variable"),
    value_target_raw = c("area", "area", "area"),
    value_target = c("area", "area", "area")
  )

  error_message <- tryCatch(
    {
      validate_canonical_rules(
        rules_dt = rules_dt,
        dataset_dt = dataset_dt,
        rule_file_id = "clean_footnotes.xlsx",
        rule_file_path = "C:/rules/clean_footnotes.xlsx",
        stage_name = "clean"
      )

      NA_character_
    },
    error = function(condition_value) {
      conditionMessage(condition_value)
    }
  )

  testthat::expect_match(
    error_message,
    "rule file location",
    ignore.case = TRUE
  )
  testthat::expect_match(
    error_message,
    "C:/rules/clean_footnotes.xlsx",
    fixed = TRUE
  )
  testthat::expect_match(error_message, "uniqueness key", ignore.case = TRUE)
  testthat::expect_match(error_message, "duplicate key #1", ignore.case = TRUE)
  testthat::expect_match(error_message, "rows=\\[1, 2, 3\\]")
})


# --- encode / decode target rule values --------------------------------------

testthat::test_that("encode_target_rule_value replaces empty and NA with placeholder", {
  constants <- get_pipeline_constants()
  result <- encode_target_rule_value(c("value", "", NA_character_))

  testthat::expect_equal(result[1], "value")
  testthat::expect_equal(result[2], constants$na_placeholder)
  testthat::expect_equal(result[3], constants$na_placeholder)
})

testthat::test_that("decode_target_rule_value restores placeholder to NA", {
  constants <- get_pipeline_constants()
  result <- decode_target_rule_value(c("value", constants$na_placeholder))

  testthat::expect_equal(result[1], "value")
  testthat::expect_true(is.na(result[2]))
})


# --- encode_rule_match_key ---------------------------------------------------

testthat::test_that("encode_rule_match_key normalizes values and encodes NA", {
  constants <- get_pipeline_constants()
  result <- encode_rule_match_key(c("Hello World", NA_character_))

  testthat::expect_equal(result[1], "hello world")
  testthat::expect_equal(result[2], constants$na_match_key)
})

testthat::test_that("resolve_target_update_strategy supports per-column overrides", {
  testthat::expect_equal(
    resolve_target_update_strategy("notes"),
    "concatenate"
  )
  testthat::expect_equal(
    resolve_target_update_strategy("unit"),
    "last_rule_wins"
  )
})

testthat::test_that("resolve_tokenized_target_condition_columns includes concatenate targets and footnotes", {
  tokenized_columns <- resolve_tokenized_target_condition_columns()

  testthat::expect_true("notes" %in% tokenized_columns)
  testthat::expect_true("footnotes" %in% tokenized_columns)
})

testthat::test_that("match_rule_target_condition_values supports tokenized matching", {
  current_values <- c("borders: 1937; source a", "borders: 1945", NA_character_)
  condition_values <- c("borders: 1937", "borders: 1937", NA_character_)

  result <- match_rule_target_condition_values(
    current_values = current_values,
    condition_values = condition_values,
    tokenized_target = TRUE
  )

  testthat::expect_identical(result, c(TRUE, FALSE, TRUE))
})


# --- apply_conditional_rule_group --------------------------------------------

testthat::test_that("apply_conditional_rule_group applies clean rules", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg")
  )

  group_rules <- data.table::data.table(
    column_source = "commodity",
    value_source_raw = "Wheat",
    value_source = NA_character_,
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram"
  )

  result <- apply_conditional_rule_group(
    dataset_dt = dataset_dt,
    group_rules = group_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true(is.list(result))
  testthat::expect_true("data" %in% names(result))
  testthat::expect_true("audit" %in% names(result))
  testthat::expect_equal(result$data$unit[[1]], "kilogram")
  testthat::expect_equal(result$data$unit[[2]], "kg")
  testthat::expect_true(nrow(result$audit) >= 1L)
})

testthat::test_that("apply_conditional_rule_group matches NA keys", {
  dataset_dt <- data.table::data.table(
    commodity = c(NA_character_, "Wheat"),
    unit = c(NA_character_, "kg")
  )

  group_rules <- data.table::data.table(
    column_source = "commodity",
    value_source_raw = NA_character_,
    value_source = NA_character_,
    column_target = "unit",
    value_target_raw = NA_character_,
    value_target = "unknown_unit"
  )

  result <- apply_conditional_rule_group(
    dataset_dt = dataset_dt,
    group_rules = group_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$unit[[1]], "unknown_unit")
  testthat::expect_equal(result$data$unit[[2]], "kg")
  testthat::expect_equal(result$audit$affected_rows[[1]], 1L)
})

testthat::test_that("apply_conditional_rule_group applies empty target as NA", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg")
  )

  group_rules <- data.table::data.table(
    column_source = "commodity",
    value_source_raw = "Wheat",
    value_source = NA_character_,
    column_target = "unit",
    value_target_raw = "kg",
    value_target = ""
  )

  result <- apply_conditional_rule_group(
    dataset_dt = dataset_dt,
    group_rules = group_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true(is.na(result$data$unit[[1]]))
  testthat::expect_equal(result$data$unit[[2]], "kg")
})

testthat::test_that("apply_conditional_rule_group matches concatenated notes target conditions", {
  dataset_dt <- data.table::data.table(
    hemisphere = "total__HEMISPHERE_PLACEHOLDER__north borders: 1937",
    notes = "borders: 1937; iia"
  )

  group_rules <- data.table::data.table(
    column_source = "hemisphere",
    value_source_raw = "total__HEMISPHERE_PLACEHOLDER__north borders: 1937",
    value_source = "north",
    column_target = "notes",
    value_target_raw = "borders: 1937",
    value_target = NA_character_
  )

  result <- apply_conditional_rule_group(
    dataset_dt = dataset_dt,
    group_rules = group_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$hemisphere[[1]], "north")
})

testthat::test_that("apply_conditional_rule_group does not audit normalize-equivalent no-op matches", {
  dataset_dt <- data.table::data.table(
    footnotes = "__australian mandate__"
  )

  group_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "australian mandate",
    value_source = "__australian mandate__",
    column_target = "footnotes",
    value_target_raw = "australian mandate",
    value_target = "__australian mandate__"
  )

  result <- apply_conditional_rule_group(
    dataset_dt = dataset_dt,
    group_rules = group_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$footnotes[[1]], "__australian mandate__")
  testthat::expect_equal(nrow(result$audit), 0L)
})


# --- apply_rule_payload ------------------------------------------------------

testthat::test_that("apply_rule_payload applies multiple rule groups", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg"),
    variable = c("Prod", "Prod")
  )

  canonical_rules <- data.table::data.table(
    column_source = c("commodity", "commodity"),
    value_source_raw = c("Wheat", "Rice"),
    value_source = c(NA_character_, NA_character_),
    column_target = c("unit", "unit"),
    value_target_raw = c("kg", "kg"),
    value_target = c("kilogram", "gram")
  )

  result <- apply_rule_payload(
    dataset_dt = dataset_dt,
    canonical_rules = canonical_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true(is.list(result))
  testthat::expect_equal(result$data$unit[[1]], "kilogram")
  testthat::expect_equal(result$data$unit[[2]], "gram")
  testthat::expect_true(nrow(result$audit) >= 2L)
})

testthat::test_that("apply_rule_payload returns empty audit for zero rules", {
  dataset_dt <- data.table::data.table(commodity = "Wheat", unit = "kg")

  result <- apply_rule_payload(
    dataset_dt = dataset_dt,
    canonical_rules = data.table::data.table(),
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true(is.list(result))
  testthat::expect_equal(nrow(result$audit), 0L)
})

testthat::test_that("apply_rule_payload prepared execution plan matches direct execution", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg"),
    variable = c("Prod", "Prod")
  )

  canonical_rules <- data.table::data.table(
    column_source = c("commodity", "commodity"),
    value_source_raw = c("Wheat", "Rice"),
    value_source = c(NA_character_, NA_character_),
    column_target = c("unit", "unit"),
    value_target_raw = c("kg", "kg"),
    value_target = c("kilogram", "gram")
  )

  prepared_payload <- prepare_rule_payload_execution_plan(
    canonical_rules = canonical_rules,
    stage_name = "clean"
  )

  direct_result <- apply_rule_payload(
    dataset_dt = data.table::copy(dataset_dt),
    canonical_rules = canonical_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  prepared_result <- apply_rule_payload(
    dataset_dt = data.table::copy(dataset_dt),
    canonical_rules = canonical_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z",
    prepared_payload = prepared_payload
  )

  testthat::expect_equal(prepared_result$data, direct_result$data)
  testthat::expect_equal(prepared_result$audit, direct_result$audit)
  testthat::expect_equal(
    prepared_result$changed_value_count,
    direct_result$changed_value_count
  )
})

testthat::test_that("apply_rule_payload trigger_columns filters execution to dependent groups", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg"),
    variable = c("Prod", "Prod"),
    notes = c("old", "old")
  )

  canonical_rules <- data.table::data.table(
    column_source = c("commodity", "variable"),
    value_source_raw = c("Wheat", "Prod"),
    value_source = c(NA_character_, NA_character_),
    column_target = c("unit", "notes"),
    value_target_raw = c("kg", "old"),
    value_target = c("kilogram", "commodityion-note")
  )

  prepared_payload <- prepare_rule_payload_execution_plan(
    canonical_rules = canonical_rules,
    stage_name = "clean"
  )

  filtered_result <- apply_rule_payload(
    dataset_dt = data.table::copy(dataset_dt),
    canonical_rules = canonical_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z",
    prepared_payload = prepared_payload,
    trigger_columns = c("commodity")
  )

  testthat::expect_equal(filtered_result$data$unit[[1]], "kilogram")
  testthat::expect_equal(filtered_result$data$notes[[1]], "old")
  testthat::expect_true("unit" %in% filtered_result$changed_columns)
  testthat::expect_false("notes" %in% filtered_result$changed_columns)
})

testthat::test_that("apply_conditional_rule_group enforces exactly one group payload input", {
  dataset_dt <- data.table::data.table(commodity = "Wheat", unit = "kg")
  group_rules <- data.table::data.table(
    column_source = "commodity",
    value_source_raw = "Wheat",
    value_source = NA_character_,
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram"
  )

  prepared_group <- prepare_conditional_rule_group(
    group_rules = group_rules,
    stage_name = "clean"
  )

  testthat::expect_error(
    apply_conditional_rule_group(
      dataset_dt = data.table::copy(dataset_dt),
      group_rules = NULL,
      prepared_group = NULL,
      stage_name = "clean",
      dataset_name = "demo",
      rule_file_id = "test.xlsx",
      execution_timestamp_utc = "2026-01-01T00:00:00Z"
    ),
    "exactly one"
  )

  testthat::expect_error(
    apply_conditional_rule_group(
      dataset_dt = data.table::copy(dataset_dt),
      group_rules = group_rules,
      prepared_group = prepared_group,
      stage_name = "clean",
      dataset_name = "demo",
      rule_file_id = "test.xlsx",
      execution_timestamp_utc = "2026-01-01T00:00:00Z"
    ),
    "exactly one"
  )
})


# --- apply_footnote_rules ----------------------------------------------------

testthat::test_that("apply_footnote_rules replaces a single footnote", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    footnotes = c("old note", "other note")
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "old note",
    value_source = "new note",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true(is.list(result))
  testthat::expect_equal(result$data$footnotes[[1]], "new note")
  testthat::expect_equal(result$data$footnotes[[2]], "other note")
  testthat::expect_true(nrow(result$audit) >= 1L)
})

testthat::test_that("apply_footnote_rules removes a single footnote to NA", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat"),
    footnotes = c("remove me")
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "remove me",
    value_source = NA_character_,
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true(is.na(result$data$footnotes[[1]]))
})

testthat::test_that("apply_footnote_rules handles multi-footnote split and reconstruct", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat"),
    footnotes = c("note A; note B; note C")
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "note B",
    value_source = "replaced B",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(
    result$data$footnotes[[1]],
    "note A; replaced B; note C"
  )
})

testthat::test_that("apply_footnote_rules preserves footnote order", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    footnotes = "first; second; third"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "second",
    value_source = "2nd",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$footnotes[[1]], "first; 2nd; third")
})

testthat::test_that("apply_footnote_rules removes one footnote from multi-footnote cell", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    footnotes = "keep A; remove me; keep B"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "remove me",
    value_source = NA_character_,
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$footnotes[[1]], "keep A; keep B")
})

testthat::test_that("apply_footnote_rules sets NA when all footnotes removed", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    footnotes = "del A; del B"
  )

  footnote_rules <- data.table::data.table(
    column_source = c("footnotes", "footnotes"),
    value_source_raw = c("del A", "del B"),
    value_source = c(NA_character_, NA_character_),
    column_target = c("footnotes", "footnotes"),
    value_target_raw = c(NA_character_, NA_character_),
    value_target = c(NA_character_, NA_character_)
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true(is.na(result$data$footnotes[[1]]))
})

testthat::test_that("apply_footnote_rules preserves unmatched footnotes", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    footnotes = "unmatched note; matched note"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "matched note",
    value_source = "replaced",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$footnotes[[1]], "unmatched note; replaced")
})

testthat::test_that("apply_footnote_rules handles comma-containing footnotes", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    footnotes = "note with, comma; simple note"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "note with, comma",
    value_source = "comma preserved",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(
    result$data$footnotes[[1]],
    "comma preserved; simple note"
  )
})

testthat::test_that("apply_footnote_rules applies target column updates", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    unit = "kg",
    footnotes = "update unit"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "update unit",
    value_source = NA_character_,
    column_target = "unit",
    value_target_raw = NA_character_,
    value_target = "kilogram"
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$unit[[1]], "kilogram")
})

testthat::test_that("apply_footnote_rules concatenates mapped notes values", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    notes = NA_character_,
    footnotes = "fn_country; fn_continent; fn_note_01; fn_note_02"
  )

  footnote_rules <- data.table::data.table(
    column_source = c("footnotes", "footnotes"),
    value_source_raw = c("fn_note_01", "fn_note_02"),
    value_source = c(NA_character_, NA_character_),
    column_target = c("notes", "notes"),
    value_target_raw = c(NA_character_, NA_character_),
    value_target = c("note_01", "note_02")
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(
    result$data$footnotes[[1]],
    "fn_country; fn_continent"
  )
  testthat::expect_equal(result$data$notes[[1]], "note_01; note_02")
})

testthat::test_that("apply_footnote_rules appends concatenated notes to existing notes", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    notes = "existing note",
    footnotes = "fn_note_01; fn_note_02"
  )

  footnote_rules <- data.table::data.table(
    column_source = c("footnotes", "footnotes"),
    value_source_raw = c("fn_note_01", "fn_note_02"),
    value_source = c(NA_character_, NA_character_),
    column_target = c("notes", "notes"),
    value_target_raw = c(NA_character_, NA_character_),
    value_target = c("note_01", "note_02")
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(
    result$data$notes[[1]],
    "existing note; note_01; note_02"
  )
})

testthat::test_that("apply_footnote_rules deduplicates concatenated notes values", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    notes = "composition: unspec",
    footnotes = "fn_note_dup"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "fn_note_dup",
    value_source = NA_character_,
    column_target = "notes",
    value_target_raw = NA_character_,
    value_target = "composition: unspec"
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$notes[[1]], "composition: unspec")
})

testthat::test_that("apply_footnote_rules handles NA footnotes rows", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    footnotes = c(NA_character_, "some note")
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "some note",
    value_source = "replaced",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true(is.na(result$data$footnotes[[1]]))
  testthat::expect_equal(result$data$footnotes[[2]], "replaced")
})

testthat::test_that("apply_footnote_rules cleans temporary columns", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    footnotes = "note"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "note",
    value_source = "new",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_false("row_id" %in% names(result$data))
  testthat::expect_false("footnote_index" %in% names(result$data))
})

testthat::test_that("apply_footnote_rules generates compatible audit structure", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    footnotes = "test note"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "test note",
    value_source = "replaced",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  expected_columns <- c(
    "dataset_name",
    "column_source",
    "value_source_raw",
    "value_source_result",
    "column_target",
    "value_target_raw",
    "value_target_result",
    "affected_rows",
    "execution_timestamp_utc",
    "rule_file_identifier",
    "execution_stage"
  )
  testthat::expect_true(all(expected_columns %in% names(result$audit)))
  testthat::expect_equal(result$audit$dataset_name[[1]], "demo")
  testthat::expect_equal(result$audit$column_source[[1]], "footnotes")
  testthat::expect_equal(result$audit$execution_stage[[1]], "clean")
  testthat::expect_equal(result$audit$rule_file_identifier[[1]], "test.xlsx")
})

testthat::test_that("apply_footnote_rules works with harmonize stage", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    footnotes = "harmonize me"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "harmonize me",
    value_source = "harmonize",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "harmonize",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$footnotes[[1]], "harmonize")
  testthat::expect_equal(result$audit$execution_stage[[1]], "harmonize")
})

testthat::test_that("apply_footnote_rules does not audit normalize-equivalent no-op matches", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    footnotes = "__australian mandate__"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "australian mandate",
    value_source = "__australian mandate__",
    column_target = "footnotes",
    value_target_raw = "australian mandate",
    value_target = "__australian mandate__"
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$footnotes[[1]], "__australian mandate__")
  testthat::expect_equal(nrow(result$audit), 0L)
})

testthat::test_that("apply_rule_payload routes footnote rules to apply_footnote_rules", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg"),
    footnotes = c("fn A; fn B", "fn C")
  )

  canonical_rules <- data.table::data.table(
    column_source = c("footnotes", "commodity"),
    value_source_raw = c("fn A", "Rice"),
    value_source = c("replaced A", NA_character_),
    column_target = c("footnotes", "unit"),
    value_target_raw = c(NA_character_, "kg"),
    value_target = c(NA_character_, "gram")
  )

  result <- apply_rule_payload(
    dataset_dt = dataset_dt,
    canonical_rules = canonical_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$footnotes[[1]], "replaced A; fn B")
  testthat::expect_equal(result$data$unit[[2]], "gram")
  testthat::expect_true(nrow(result$audit) >= 2L)
})

testthat::test_that("apply_footnote_rules detects conflicting target updates", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    unit = "kg",
    footnotes = "fn1; fn2"
  )

  footnote_rules <- data.table::data.table(
    column_source = c("footnotes", "footnotes"),
    value_source_raw = c("fn1", "fn2"),
    value_source = c(NA_character_, NA_character_),
    column_target = c("unit", "unit"),
    value_target_raw = c(NA_character_, NA_character_),
    value_target = c("kilogram", "gram")
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  # last rule wins deterministically
  testthat::expect_true(result$data$unit[[1]] %in% c("kilogram", "gram"))
  testthat::expect_true(nrow(result$audit) >= 2L)
})

testthat::test_that("apply_footnote_rules adds missing footnotes column", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    unit = "kg"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "any",
    value_source = "replaced",
    column_target = "footnotes",
    value_target_raw = NA_character_,
    value_target = NA_character_
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true("footnotes" %in% names(result$data))
})

testthat::test_that("apply_footnote_rules applies conditional target updates", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    unit = "kg",
    footnotes = "conditional fn"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "conditional fn",
    value_source = NA_character_,
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram"
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$unit[[1]], "kilogram")
  testthat::expect_true(is.na(result$data$footnotes[[1]]))
})

testthat::test_that("apply_footnote_rules skips conditional update when condition not met", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    unit = "tonnes",
    footnotes = "conditional fn"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "conditional fn",
    value_source = NA_character_,
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram"
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$unit[[1]], "tonnes")
  testthat::expect_equal(result$data$footnotes[[1]], "conditional fn")
})

testthat::test_that("apply_footnote_rules skips source rewrite when target condition is not met", {
  dataset_dt <- data.table::data.table(
    commodity = "bovine",
    footnotes = "large"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "large",
    value_source = "__VACAS_VIEJAS_TEST__",
    column_target = "commodity",
    value_target_raw = "cattle",
    value_target = "cattle:__VACAS_VIEJAS_TEST__"
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$commodity[[1]], "bovine")
  testthat::expect_equal(result$data$footnotes[[1]], "large")
})

testthat::test_that("apply_footnote_rules matches concatenated notes target conditions", {
  dataset_dt <- data.table::data.table(
    commodity = "Wheat",
    notes = "borders: 1937; iia",
    footnotes = "conditional fn"
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "conditional fn",
    value_source = NA_character_,
    column_target = "notes",
    value_target_raw = "borders: 1937",
    value_target = "matched-note"
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(
    result$data$notes[[1]],
    "borders: 1937; iia; matched-note"
  )
  testthat::expect_true(is.na(result$data$footnotes[[1]]))
})

testthat::test_that("__ANY__ target-condition skips append when note already exists", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    notes = c("composition: unspec", "quality: high"),
    footnotes = c("conditional fn", "conditional fn")
  )

  footnote_rules <- data.table::data.table(
    column_source = "footnotes",
    value_source_raw = "conditional fn",
    value_source = NA_character_,
    column_target = "notes",
    value_target_raw = "__ANY__",
    value_target = "composition: unspec"
  )

  result <- apply_footnote_rules(
    dataset_dt = dataset_dt,
    footnote_rules = footnote_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "test.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$notes[[1]], "composition: unspec")
  testthat::expect_equal(
    result$data$notes[[2]],
    "quality: high; composition: unspec"
  )
})
