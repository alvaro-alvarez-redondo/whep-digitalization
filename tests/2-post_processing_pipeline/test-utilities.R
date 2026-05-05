# tests/2-postpro_pipeline/test-utilities.R
# unit tests for R/2-postpro_pipeline/21-postpro_utilities.R

source(here::here("tests", "test_helper.R"), echo = FALSE)
source(
  here::here("r", "2-postpro_pipeline", "run_postpro_pipeline.R"),
  echo = FALSE
)


# --- get_canonical_rule_columns ----------------------------------------------

testthat::test_that("get_canonical_rule_columns returns correct columns", {
  result <- get_canonical_rule_columns()

  testthat::expect_true(is.character(result))
  testthat::expect_true("column_source" %in% result)
  testthat::expect_true("value_source_raw" %in% result)
  testthat::expect_true("column_target" %in% result)
  testthat::expect_true("value_target_raw" %in% result)
  testthat::expect_true("value_target" %in% result)
})


# --- get_postpro_stage_names -----------------------------------------

testthat::test_that("get_postpro_stage_names returns clean and harmonize", {
  result <- get_postpro_stage_names()

  testthat::expect_identical(result, c("clean", "harmonize"))
})


# --- validate_postpro_stage_name -------------------------------------

testthat::test_that("validate_postpro_stage_name accepts valid stages", {
  testthat::expect_identical(
    validate_postpro_stage_name("clean"),
    "clean"
  )
  testthat::expect_identical(
    validate_postpro_stage_name("harmonize"),
    "harmonize"
  )
})

testthat::test_that("validate_postpro_stage_name rejects invalid stages", {
  testthat::expect_error(validate_postpro_stage_name("invalid"))
  testthat::expect_error(validate_postpro_stage_name(""))
})


# --- get_stage_target_value_column -------------------------------------------

testthat::test_that("get_stage_target_value_column returns stage-specific column", {
  testthat::expect_identical(
    get_stage_target_value_column("clean"),
    "value_target"
  )
  testthat::expect_identical(
    get_stage_target_value_column("harmonize"),
    "value_target"
  )
})


# --- get_stage_source_value_column -------------------------------------------

testthat::test_that("get_stage_source_value_column returns stage-specific column", {
  testthat::expect_identical(
    get_stage_source_value_column("clean"),
    "value_source"
  )
  testthat::expect_identical(
    get_stage_source_value_column("harmonize"),
    "value_source"
  )
})


# --- read_rule_table ---------------------------------------------------------

testthat::test_that("read_rule_table reads CSV rule files", {
  root_dir <- build_temp_dir("whep-read-rules-")
  file_path <- file.path(root_dir, "rules.csv")

  rules <- data.frame(
    column_source = "commodity",
    value_source_raw = "Wheat",
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram",
    stringsAsFactors = FALSE
  )
  readr::write_csv(rules, file_path)

  result <- read_rule_table(file_path)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_equal(nrow(result), 1L)
})

testthat::test_that("read_rule_table reads Excel rule files", {
  root_dir <- build_temp_dir("whep-read-rules-xlsx-")
  file_path <- file.path(root_dir, "rules.xlsx")

  rules <- data.frame(
    column_source = "commodity",
    value_source_raw = "Wheat",
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram",
    stringsAsFactors = FALSE
  )
  create_test_xlsx(rules, file_path)

  result <- read_rule_table(file_path)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_equal(nrow(result), 1L)
})

testthat::test_that("read_rule_table reads all matching Excel worksheets", {
  root_dir <- build_temp_dir("whep-read-rules-xlsx-multi-")
  file_path <- file.path(root_dir, "rules.xlsx")

  sheet_one <- data.frame(
    column_source = "commodity",
    value_source_raw = "Wheat",
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram",
    stringsAsFactors = FALSE
  )

  sheet_two <- data.frame(
    clean_column_source = "unit",
    clean_value_source_raw = "kg",
    clean_column_target = "notes",
    clean_value_target_raw = NA_character_,
    clean_value_target = "standardized unit",
    stringsAsFactors = FALSE
  )

  non_matching <- data.frame(
    note = "this sheet should be ignored",
    stringsAsFactors = FALSE
  )

  writexl::write_xlsx(
    list(
      matching_first = sheet_one,
      metadata = non_matching,
      matching_second = sheet_two
    ),
    path = file_path
  )

  result <- read_rule_table(file_path)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_equal(
    as.character(result$column_source),
    c("commodity", "unit")
  )
  testthat::expect_false("note" %in% names(result))
})

testthat::test_that("read_rule_table errors when no Excel worksheet matches rule schema", {
  root_dir <- build_temp_dir("whep-read-rules-xlsx-no-match-")
  file_path <- file.path(root_dir, "rules.xlsx")

  writexl::write_xlsx(
    list(
      metadata = data.frame(
        note = "not a rule table",
        stringsAsFactors = FALSE
      ),
      diagnostics = data.frame(status = "ok", stringsAsFactors = FALSE)
    ),
    path = file_path
  )

  testthat::expect_error(
    read_rule_table(file_path),
    "(?i)No\\s+worksheets\\s+with\\s+matching\\s+rule\\s+columns\\s+found"
  )
})


# --- load_stage_rule_payloads ------------------------------------------------

testthat::test_that("load_stage_rule_payloads discovers rule files for a stage", {
  config <- build_test_config()

  rules <- data.frame(
    column_source = "commodity",
    value_source_raw = "Wheat",
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram",
    stringsAsFactors = FALSE
  )
  readr::write_csv(
    rules,
    file.path(config$paths$data$import$cleaning, "clean_rules_test.csv")
  )

  result <- load_stage_rule_payloads(config = config, stage_name = "clean")
  expected_rule_path <- normalizePath(
    file.path(config$paths$data$import$cleaning, "clean_rules_test.csv"),
    winslash = "/",
    mustWork = FALSE
  )

  testthat::expect_true(is.list(result))
  testthat::expect_true(length(result) >= 1L)
  testthat::expect_true("rule_file_id" %in% names(result[[1]]))
  testthat::expect_true("rule_file_path" %in% names(result[[1]]))
  testthat::expect_true("raw_rules" %in% names(result[[1]]))
  testthat::expect_identical(result[[1]]$rule_file_path, expected_rule_path)
})

testthat::test_that("load_stage_rule_payloads returns empty list for empty directory", {
  config <- build_test_config()

  result <- load_stage_rule_payloads(config = config, stage_name = "harmonize")

  testthat::expect_true(is.list(result))
  testthat::expect_equal(length(result), 0L)
})


# --- generate_postpro_rule_templates ---------------------------------

testthat::test_that("generate_postpro_rule_templates writes templates", {
  config <- build_test_config()

  template_paths <- generate_postpro_rule_templates(
    config = config,
    overwrite = TRUE
  )

  testthat::expect_true("clean_harmonize_template" %in% names(template_paths))
  testthat::expect_true(all(file.exists(unname(template_paths))))
  testthat::expect_match(
    basename(template_paths[["clean_harmonize_template"]]),
    "^clean_harmonize_template\\.xlsx$"
  )
})


# --- build_layer_diagnostics -------------------------------------------------

testthat::test_that("build_layer_diagnostics returns structured diagnostics", {
  audit_dt <- data.table::data.table(
    affected_rows = c(5L, 3L)
  )

  result <- build_layer_diagnostics(
    layer_name = "clean",
    rows_in = 100L,
    rows_out = 100L,
    audit_dt = audit_dt
  )

  testthat::expect_true(is.list(result))
  testthat::expect_identical(result$layer_name, "clean")
  testthat::expect_identical(result$rows_in, 100L)
  testthat::expect_identical(result$rows_out, 100L)
  testthat::expect_identical(result$matched_count, 8L)
})
