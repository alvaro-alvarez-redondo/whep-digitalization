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
  "13-output/13-validate.R",
  "13-output/13-output.R"
)
purrr::walk(import_scripts, \(script_name) {
  source(here::here("r", "1-import_pipeline", script_name), echo = FALSE)
})


testthat::test_that("identify_year_columns detects single and range year columns", {
  dt <- data.table::data.table(
    continent = "asia",
    country = "japan",
    `2020` = "1",
    `2020-2021` = "2",
    `x2020` = "3"
  )
  cfg <- build_test_config()

  years <- identify_year_columns(dt, cfg)

  testthat::expect_true("2020" %in% years)
  testthat::expect_true("2020-2021" %in% years)
  testthat::expect_false("x2020" %in% years)
})


testthat::test_that("normalize_key_fields normalizes expected text columns", {
  dt <- data.table::data.table(
    variable = c("commodityion", "Trade"),
    continent = c("Asía", "Europé"),
    country = c("Jápan", "Fránce"),
    footnotes = c("note 1/ Revised", "prel.; #2")
  )
  cfg <- build_test_config()

  out <- normalize_key_fields(dt, "Cérèals", cfg)

  testthat::expect_true(all(out$commodity == "cereals"))
  testthat::expect_identical(out$variable, c("commodityion", "trade"))
  testthat::expect_identical(out$continent, c("asia", "europe"))
  testthat::expect_identical(out$country, c("japan", "france"))
  testthat::expect_true(all(!is.na(out$footnotes)))
})


testthat::test_that("extract_file_metadata parses yearbook and commodity deterministically", {
  file_paths <- c(
    "data/1-import/10-raw_import/whep_yb_2020_2021_a_b_wheat.xlsx",
    "data/1-import/10-raw_import/whep_yb_2019_2020_c_d_rice_grain.xlsx",
    "data/1-import/10-raw_import/invalid_name.xlsx"
  )

  out <- extract_file_metadata(file_paths)

  testthat::expect_equal(out$yearbook[[1]], "yb_2020")
  testthat::expect_equal(out$commodity[[1]], "wheat")
  testthat::expect_equal(out$yearbook[[2]], "yb_2019")
  testthat::expect_equal(out$commodity[[2]], "rice_grain")
  testthat::expect_true(is.na(out$yearbook[[3]]))
  testthat::expect_true(is.na(out$commodity[[3]]))
})


testthat::test_that("reshape_to_long preserves configured id columns", {
  dt <- data.table::data.table(
    hemisphere = c("north", "south"),
    continent = c("asia", "africa"),
    country = c("japan", "kenya"),
    commodity = c("wheat", "rice"),
    variable = c("commodityion", "commodityion"),
    unit = c("tonnes", "tonnes"),
    footnotes = c(NA_character_, NA_character_),
    `2020` = c("100", "200"),
    `2021` = c("110", "210")
  )
  cfg <- build_test_config()

  out <- reshape_to_long(dt, cfg)

  testthat::expect_equal(nrow(out), 4L)
  testthat::expect_true(all(
    c("hemisphere", "country", "year", "value") %in% names(out)
  ))
})


testthat::test_that("reshape_to_long handles single-year inputs without changing contract", {
  dt <- data.table::data.table(
    hemisphere = c("north", "south"),
    continent = c("asia", "africa"),
    country = c("japan", "kenya"),
    commodity = c("wheat", "rice"),
    variable = c("commodityion", "commodityion"),
    unit = c("tonnes", "tonnes"),
    footnotes = c(NA_character_, NA_character_),
    `2020` = c("100", "200")
  )
  cfg <- build_test_config()

  out <- reshape_to_long(dt, cfg)

  testthat::expect_equal(nrow(out), 2L)
  testthat::expect_identical(unique(out$year), "2020")
  testthat::expect_identical(out$value, c("100", "200"))
  testthat::expect_true(all(
    c("hemisphere", "country", "year", "value") %in% names(out)
  ))
})


testthat::test_that("read_file_sheets combines sheet data and reports missing base columns", {
  root_dir <- build_temp_dir("whep-import-read-file-sheets-")
  file_path <- file.path(root_dir, "whep_yb_2020_2021_a_b_wheat.xlsx")

  workbook <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(workbook, "Sheet_OK")
  openxlsx::writeData(
    workbook,
    "Sheet_OK",
    data.frame(
      continent = "asia",
      country = "japan",
      `2020` = "100",
      stringsAsFactors = FALSE
    )
  )
  openxlsx::addWorksheet(workbook, "Sheet_Missing")
  openxlsx::writeData(
    workbook,
    "Sheet_Missing",
    data.frame(note = "missing base columns", stringsAsFactors = FALSE)
  )
  openxlsx::saveWorkbook(workbook, file_path, overwrite = TRUE)

  cfg <- build_test_config(root_dir)
  out <- read_file_sheets(file_path, cfg)

  testthat::expect_true(is.list(out))
  testthat::expect_s3_class(out$data, "data.table")
  testthat::expect_true("variable" %in% names(out$data))
  testthat::expect_true(any(out$data$variable == "Sheet_OK"))
  testthat::expect_true(length(out$errors) >= 1L)
})


testthat::test_that("read_workbook_batch returns deterministic workbook-aligned results", {
  root_dir <- build_temp_dir("whep-import-read-workbook-batch-")
  file_a <- file.path(root_dir, "whep_yb_2020_2021_a_b_wheat.xlsx")
  file_b <- file.path(root_dir, "whep_yb_2020_2021_c_d_rice.xlsx")

  create_test_xlsx(
    data.frame(continent = "asia", country = "japan", `2020` = "100"),
    file_a
  )
  create_test_xlsx(
    data.frame(continent = "europe", country = "france", `2020` = "200"),
    file_b
  )

  cfg <- build_test_config(root_dir)
  out <- read_workbook_batch(c(file_a, file_b), cfg)

  testthat::expect_true(is.list(out))
  testthat::expect_equal(length(out$read_data_list), 2L)
  testthat::expect_true(all(vapply(
    out$read_data_list,
    data.table::is.data.table,
    logical(1)
  )))
  testthat::expect_true(is.character(out$errors))
})


testthat::test_that("read_workbook_batch reuses provided workbook sheet map deterministically", {
  root_dir <- build_temp_dir("whep-import-read-workbook-batch-sheet-map-")
  file_a <- file.path(root_dir, "whep_yb_2020_2021_a_b_wheat.xlsx")

  workbook <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(workbook, "Sheet_A")
  openxlsx::writeData(
    workbook,
    "Sheet_A",
    data.frame(continent = "asia", country = "japan", `2020` = "100")
  )
  openxlsx::addWorksheet(workbook, "Sheet_B")
  openxlsx::writeData(
    workbook,
    "Sheet_B",
    data.frame(continent = "europe", country = "france", `2020` = "200")
  )
  openxlsx::saveWorkbook(workbook, file_a, overwrite = TRUE)

  cfg <- build_test_config(root_dir)
  sheet_map <- stats::setNames(list(c("Sheet_B")), file_a)

  out <- read_workbook_batch(
    file_paths = c(file_a),
    config = cfg,
    sheet_names_by_file = sheet_map
  )

  testthat::expect_equal(length(out$read_data_list), 1L)
  testthat::expect_s3_class(out$read_data_list[[1]], "data.table")
  testthat::expect_true(all(out$read_data_list[[1]]$variable == "Sheet_B"))
})


testthat::test_that("convert_year_columns stores detected year-column cache", {
  dt <- data.table::data.table(
    continent = "asia",
    country = "japan",
    `2020` = "100",
    `2021` = "110"
  )
  cfg <- build_test_config()

  out <- convert_year_columns(dt, cfg)

  testthat::expect_identical(
    attr(out, "whep_year_columns", exact = TRUE),
    c("2020", "2021")
  )
})


testthat::test_that("validate_mandatory_fields_dt uses centralized unknown document default", {
  dt <- data.table::data.table(
    continent = c("asia"),
    country = c(""),
    commodity = c("wheat"),
    variable = c("commodityion")
  )
  cfg <- build_test_config()
  constants <- get_pipeline_constants()

  out <- validate_mandatory_fields_dt(dt, cfg)

  testthat::expect_identical(
    out$data$document[[1]],
    constants$defaults$unknown_document
  )
  testthat::expect_true(length(out$errors) > 0L)
})
