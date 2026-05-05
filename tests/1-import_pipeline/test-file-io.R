# tests/1-import_pipeline/test-file-io.R
# unit tests for R/1-import_pipeline/10-file_io.R

source(here::here("tests", "test_helper.R"), echo = FALSE)
import_scripts <- c(
  "10-file_io/10-metadata.R",
  "10-file_io/10-discovery.R"
)
purrr::walk(import_scripts, \(script_name) {
  source(here::here("r", "1-import_pipeline", script_name), echo = FALSE)
})


# --- build_empty_file_metadata -----------------------------------------------

testthat::test_that("build_empty_file_metadata returns zero-row data.table with stable schema", {
  result <- build_empty_file_metadata()

  testthat::expect_true(is.data.frame(result))
  testthat::expect_equal(nrow(result), 0L)
  testthat::expect_true("file_path" %in% names(result))
  testthat::expect_true("file_name" %in% names(result))
})


# --- extract_file_metadata ---------------------------------------------------

testthat::test_that("extract_file_metadata extracts file names and paths", {
  root_dir <- build_temp_dir("whep-file-io-")
  raw_dir <- file.path(root_dir, "raw")
  dir.create(raw_dir, recursive = TRUE)

  # create test xlsx files
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, "Sheet1", data.frame(x = 1))
  openxlsx::saveWorkbook(
    wb,
    file.path(raw_dir, "whep_yb_2020_2021_a_b_wheat.xlsx"),
    overwrite = TRUE
  )

  files <- list.files(
    raw_dir,
    pattern = "\\.xlsx$",
    full.names = TRUE,
    recursive = TRUE
  )
  result <- extract_file_metadata(files)

  testthat::expect_true(is.data.frame(result))
  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_true("file_path" %in% names(result))
  testthat::expect_true("file_name" %in% names(result))
})


testthat::test_that("extract_file_metadata extracts yearbook and commodity in single pass", {
  root_dir <- build_temp_dir("whep-file-io-meta-")
  raw_dir <- file.path(root_dir, "raw")
  dir.create(raw_dir, recursive = TRUE)

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, "Sheet1", data.frame(x = 1))
  openxlsx::saveWorkbook(
    wb,
    file.path(raw_dir, "whep_yb_2020_2021_a_b_wheat.xlsx"),
    overwrite = TRUE
  )
  openxlsx::saveWorkbook(
    wb,
    file.path(raw_dir, "whep_yb_2019_2020_c_d_rice_grain.xlsx"),
    overwrite = TRUE
  )

  files <- sort(list.files(
    raw_dir,
    pattern = "\\.xlsx$",
    full.names = TRUE,
    recursive = TRUE
  ))
  result <- extract_file_metadata(files)

  testthat::expect_true(is.data.frame(result))
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_true("yearbook" %in% names(result))
  testthat::expect_true("commodity" %in% names(result))
  testthat::expect_true(all(!is.na(result$yearbook)))
  testthat::expect_true(all(!is.na(result$commodity)))
  testthat::expect_identical(result$yearbook, c("yb_2019", "yb_2020"))
})


# --- discover_files ----------------------------------------------------------

testthat::test_that("discover_files finds xlsx files recursively", {
  root_dir <- build_temp_dir("whep-discover-")
  sub_dir <- file.path(root_dir, "subdir")
  dir.create(sub_dir, recursive = TRUE)

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, "Sheet1", data.frame(x = 1))
  openxlsx::saveWorkbook(
    wb,
    file.path(root_dir, "file1.xlsx"),
    overwrite = TRUE
  )
  openxlsx::saveWorkbook(wb, file.path(sub_dir, "file2.xlsx"), overwrite = TRUE)

  result <- discover_files(root_dir)

  testthat::expect_true(is.data.frame(result))
  testthat::expect_equal(nrow(result), 2L)
})

testthat::test_that("discover_files returns empty metadata for empty directory", {
  root_dir <- build_temp_dir("whep-discover-empty-")

  result <- discover_files(root_dir)

  testthat::expect_true(is.data.frame(result))
  testthat::expect_equal(nrow(result), 0L)
})

testthat::test_that("discover_files ignores non-xlsx files", {
  root_dir <- build_temp_dir("whep-discover-non-xlsx-")

  file.create(file.path(root_dir, "readme.txt"))
  file.create(file.path(root_dir, "data.csv"))

  result <- discover_files(root_dir)

  testthat::expect_equal(nrow(result), 0L)
})
