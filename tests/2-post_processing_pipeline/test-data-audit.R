# tests/2-postpro_pipeline/test-data-audit.R
# unit tests for R/2-postpro_pipeline/20-data_audit.R

source(here::here("tests", "test_helper.R"), echo = FALSE)
source(
  here::here("r", "2-postpro_pipeline", "run_postpro_pipeline.R"),
  echo = FALSE
)


# --- helper: build audit test config ----------------------------------------

build_audit_test_config <- function(root_dir = NULL) {
  config <- build_test_config(root_dir)
  config$audit_columns <- c("document", "value")
  config$audit_columns_by_type <- list(
    character_non_empty = c("document"),
    numeric_string = c("value")
  )
  return(config)
}


# --- export_validation_audit_report: early return on empty data -------------

testthat::test_that("export_validation_audit_report returns NULL when audit_dt is empty and no findings", {
  config <- build_audit_test_config()
  empty_dt <- data.table::data.table(
    document = character(),
    value = character()
  )
  output_path <- file.path(build_temp_dir(), "audit.xlsx")

  result <- export_validation_audit_report(
    audit_dt = empty_dt,
    config = config,
    findings_dt = empty_audit_findings_dt(),
    output_path = output_path
  )

  testthat::expect_null(result)
  testthat::expect_false(file.exists(output_path))
})

testthat::test_that("export_validation_audit_report writes Excel when findings exist", {
  config <- build_audit_test_config()
  audit_dt <- data.table::data.table(
    document = c("a.xlsx", "b.xlsx"),
    value = c("10", "bad")
  )
  findings_dt <- data.table::data.table(
    row_index = 2L,
    audit_column = "value",
    audit_type = "numeric_string",
    audit_message = "value must contain only digits and at most one decimal point"
  )
  output_path <- file.path(build_temp_dir(), "audit.xlsx")

  result <- export_validation_audit_report(
    audit_dt = audit_dt,
    config = config,
    findings_dt = findings_dt,
    output_path = output_path
  )

  testthat::expect_equal(result, output_path)
  testthat::expect_true(file.exists(output_path))
})


# --- audit_data_output: skip Excel when no findings -------------------------

testthat::test_that("audit_data_output skips Excel generation when no findings", {
  config <- build_audit_test_config()
  dataset_dt <- data.table::data.table(
    document = c("a.xlsx", "b.xlsx"),
    value = c("10", "20"),
    continent = c("Asia", "Europe"),
    country = c("Japan", "France"),
    commodity = c("wheat", "wheat"),
    variable = c("commodityion", "commodityion"),
    unit = c("tonnes", "tonnes"),
    year = c("2020", "2021"),
    notes = c(NA_character_, NA_character_),
    footnotes = c(NA_character_, NA_character_),
    yearbook = c("yb_2024", "yb_2024")
  )

  audit_file_path <- config$paths$data$audit$audit_file_path

  result <- audit_data_output(dataset_dt, config)

  testthat::expect_s3_class(result, "data.table")
  testthat::expect_false(file.exists(audit_file_path))
})

testthat::test_that("audit_data_output creates Excel when findings exist", {
  config <- build_audit_test_config()
  dataset_dt <- data.table::data.table(
    document = c("a.xlsx", ""),
    value = c("10", "bad"),
    continent = c("Asia", "Europe"),
    country = c("Japan", "France"),
    commodity = c("wheat", "wheat"),
    variable = c("commodityion", "commodityion"),
    unit = c("tonnes", "tonnes"),
    year = c("2020", "2021"),
    notes = c(NA_character_, NA_character_),
    footnotes = c(NA_character_, NA_character_),
    yearbook = c("yb_2024", "yb_2024")
  )

  audit_file_path <- config$paths$data$audit$audit_file_path
  mirror_dir_path <- file.path(dirname(audit_file_path), "raw_import_mirror")

  result <- audit_data_output(dataset_dt, config)

  testthat::expect_s3_class(result, "data.table")
  testthat::expect_true(file.exists(audit_file_path))
  testthat::expect_false(dir.exists(mirror_dir_path))
})
