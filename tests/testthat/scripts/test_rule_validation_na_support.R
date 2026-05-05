options(
  whep.run_postpro_pipeline.auto = FALSE
)

source(here::here("tests", "test_helper.R"), echo = FALSE)

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

testthat::test_that("validate_canonical_rules allows NA in value columns for clean stage", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    variable = c("Prod", "Prod"),
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
      rule_file_id = "clean_clean_harmonize_template.xlsx",
      stage_name = "clean"
    )
  )
})

testthat::test_that("validate_canonical_rules remains fail-fast for structural required columns", {
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

  testthat::expect_error(
    validate_canonical_rules(
      rules_dt = rules_dt,
      dataset_dt = dataset_dt,
      rule_file_id = "clean_clean_harmonize_template.xlsx",
      stage_name = "clean"
    ),
    regexp = "(?i)missing\\s+values\\s+in\\s+required\\s+columns"
  )
})

testthat::test_that("apply_conditional_rule_group matches NA keys deterministically", {
  dataset_dt <- data.table::data.table(
    commodity = c(NA_character_, "Wheat"),
    unit = c(NA_character_, "kg")
  )

  group_rules <- data.table::data.table(
    column_source = "commodity",
    value_source_raw = NA_character_,
    column_target = "unit",
    value_target_raw = NA_character_,
    value_target = "unknown_unit"
  )

  result <- apply_conditional_rule_group(
    dataset_dt = dataset_dt,
    group_rules = group_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "clean_clean_harmonize_template.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_equal(result$data$unit[[1]], "unknown_unit")
  testthat::expect_equal(result$data$unit[[2]], "kg")
  testthat::expect_equal(result$audit$affected_rows[[1]], 1L)
})


testthat::test_that("validate_canonical_rules allows NA in value columns for harmonize stage", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    variable = c("Prod", "Prod")
  )

  rules_dt <- data.table::data.table(
    column_source = c("commodity", "commodity"),
    value_source_raw = c(NA_character_, "Rice"),
    value_source = c(NA_character_, NA_character_),
    column_target = c("variable", "variable"),
    value_target_raw = c(NA_character_, "Prod"),
    value_target = c(NA_character_, "commodityion")
  )

  testthat::expect_invisible(
    validate_canonical_rules(
      rules_dt = rules_dt,
      dataset_dt = dataset_dt,
      rule_file_id = "harmonize_clean_harmonize_template.xlsx",
      stage_name = "harmonize"
    )
  )
})


testthat::test_that("empty target clean value is applied as NA_character_", {
  dataset_dt <- data.table::data.table(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg")
  )

  group_rules <- data.table::data.table(
    column_source = "commodity",
    value_source_raw = "Wheat",
    column_target = "unit",
    value_target_raw = "kg",
    value_target = ""
  )

  result <- apply_conditional_rule_group(
    dataset_dt = dataset_dt,
    group_rules = group_rules,
    stage_name = "clean",
    dataset_name = "demo",
    rule_file_id = "clean_clean_harmonize_template.xlsx",
    execution_timestamp_utc = "2026-01-01T00:00:00Z"
  )

  testthat::expect_true(is.na(result$data$unit[[1]]))
  testthat::expect_equal(result$data$unit[[2]], "kg")
  testthat::expect_equal(result$audit$affected_rows[[1]], 1L)
  testthat::expect_true(is.na(result$audit$value_target_result[[1]]))
})
