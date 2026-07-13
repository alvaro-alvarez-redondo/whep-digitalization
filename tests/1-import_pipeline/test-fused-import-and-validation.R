# tests/1-import_pipeline/test-fused-import-and-validation.R
# unit tests pinning the jul4 rewrites:
# - validate_long_dt_by_document() must reproduce the split-by-document +
#   per-piece validate_long_dt() behavior exactly (rows, error strings, order)
# - read_transform_pipeline_files() must reproduce the two-stage
#   read_pipeline_files() -> transform_files_list() output exactly, while
#   ticking the progressor twice per file (the (2 * nfiles) + 4 budget)

source(here::here("tests", "test_helper.R"), echo = FALSE)
import_scripts <- c(
  "10-file_io/10-metadata.R",
  "10-file_io/10-discovery.R",
  "11-reading/11-read-utils.R",
  "11-reading/11-header-normalization.R",
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

# reference implementation: the pre-jul4 per-document loop
validate_split_reference <- function(long_dt, config) {
  validation_data_list <- split(
    long_dt,
    by = "document",
    keep.by = TRUE,
    sorted = FALSE
  )
  validation_results <- lapply(
    validation_data_list,
    function(document_dt) validate_long_dt(document_dt, config)
  )
  list(
    data = data.table::rbindlist(
      lapply(validation_results, `[[`, "data"),
      use.names = TRUE,
      fill = TRUE
    ),
    errors = unlist(
      lapply(validation_results, `[[`, "errors"),
      use.names = FALSE
    )
  )
}

build_error_fixture <- function() {
  base_doc <- function(n, doc) {
    dt <- build_sample_long_dt(n)
    dt[, document := doc]
    dt[, year := as.character(1950L + seq_len(n))]
    dt[, value := as.character(seq_len(n))]
    dt
  }
  dt <- data.table::rbindlist(list(
    base_doc(4L, "doc_a.xlsx"),
    base_doc(4L, "doc_b.xlsx"),
    # doc_a again: non-contiguous document blocks
    base_doc(2L, "doc_a.xlsx")
  ))
  # mandatory violations on columns the test config actually requires
  # (build_test_config() sets column_required = continent, polity)
  dt[1, continent := NA_character_]
  dt[2, polity := ""]
  dt[3, year := "1850"]
  dt[4, year := "1990-1980"]
  dt[5, year := "1700-3000"]
  dt[6, year := NA_character_]
  dt[7, year := ""]
  dt[8, year := "19xx"]
  dt[9, polity := NA_character_]
  # true duplicate pair spanning doc_a's two non-contiguous blocks: every
  # identity column equal (rows 1 and 10)
  duplicate_row <- dt[1]
  dt[10, names(duplicate_row) := duplicate_row]
  dt
}

# --- validate_long_dt_by_document -------------------------------------------

testthat::test_that("by-document validation reproduces the split loop exactly", {
  dt <- build_error_fixture()
  config <- build_test_config()

  reference <- validate_split_reference(data.table::copy(dt), config)
  vectorized <- validate_long_dt_by_document(data.table::copy(dt), config)

  testthat::expect_identical(vectorized$errors, reference$errors)
  testthat::expect_identical(
    lapply(as.list(vectorized$data), c),
    lapply(as.list(reference$data), c)
  )
  testthat::expect_identical(names(vectorized$data), names(reference$data))
  # the fixture must actually exercise every error family
  testthat::expect_true(any(grepl("^missing mandatory value", vectorized$errors)))
  testthat::expect_true(any(grepl("^year range", vectorized$errors)))
  testthat::expect_true(any(grepl("^year value", vectorized$errors)))
  testthat::expect_true(any(grepl("^duplicate entries detected", vectorized$errors)))
})

testthat::test_that("by-document errors are document-major in split order", {
  dt <- data.table::rbindlist(list(
    build_sample_long_dt(2L)[, document := "zeta.xlsx"],
    build_sample_long_dt(2L)[, document := "alpha.xlsx"]
  ))
  dt[1, continent := NA_character_]
  dt[2, year := "1850"]
  dt[3, polity := ""]
  config <- build_test_config()

  result <- validate_long_dt_by_document(data.table::copy(dt), config)

  # zeta appears first in the data, so its errors come first (split order is
  # first-appearance, not alphabetical), mandatory before year within a doc
  testthat::expect_length(result$errors, 3L)
  testthat::expect_match(result$errors[1], "document 'zeta.xlsx'.*continent")
  testthat::expect_match(result$errors[2], "year value '1850'")
  testthat::expect_match(result$errors[3], "document 'alpha.xlsx'.*polity")
})

testthat::test_that("by-document validation keeps the split path's empty shapes", {
  dt <- build_sample_long_dt(2L)[0L]
  config <- build_test_config()

  result <- validate_long_dt_by_document(dt, config)

  testthat::expect_null(result$errors)
  testthat::expect_identical(nrow(result$data), 0L)
})

testthat::test_that("by-document validation adds missing mandatory columns once", {
  dt <- data.table::data.table(
    commodity = c("wheat", "rice"),
    variable = c("production", "production"),
    unit = c("t", "t"),
    year = c("1950", "1951"),
    value = c("1", "2"),
    document = c("a.xlsx", "b.xlsx")
  )
  config <- build_test_config()

  result <- validate_long_dt_by_document(data.table::copy(dt), config)
  reference <- validate_split_reference(data.table::copy(dt), config)

  testthat::expect_true(all(c("continent", "polity") %in% names(result$data)))
  testthat::expect_identical(result$errors, reference$errors)
})

# --- read_transform_pipeline_files ------------------------------------------

build_wide_workbooks <- function() {
  workbook_dir <- build_temp_dir("whep-fused-")
  wide_a <- data.table::data.table(
    continent = c("Asia", "Asia"),
    polity = c("Japan", "China"),
    unit = c("t", "t"),
    `1950` = c("10", "20"),
    `1951` = c("11", "21")
  )
  wide_b <- data.table::data.table(
    continent = c("Europe"),
    polity = c("France"),
    unit = c("t"),
    `1950` = c("30")
  )
  path_a <- create_test_xlsx(wide_a, file.path(workbook_dir, "file_a.xlsx"))
  path_b <- create_test_xlsx(wide_b, file.path(workbook_dir, "file_b.xlsx"))
  data.table::data.table(
    file_path = c(path_a, path_b),
    file_name = c("file_a.xlsx", "file_b.xlsx"),
    yearbook = c("yb_1950", "yb_1950"),
    commodity = c("wheat", "barley")
  )
}

testthat::test_that("fused read+transform reproduces the two-stage output", {
  file_list_dt <- build_wide_workbooks()
  config <- build_test_config()

  read_result <- read_pipeline_files(file_list_dt, config, progressor = NULL)
  staged <- transform_files_list(
    file_list_dt,
    read_result$read_data_list,
    config,
    progressor = NULL
  )

  fused <- read_transform_pipeline_files(file_list_dt, config, progressor = NULL)

  testthat::expect_identical(fused$errors, read_result$errors)
  testthat::expect_identical(
    lapply(as.list(fused$transformed$long_raw), c),
    lapply(as.list(staged$long_raw), c)
  )
  testthat::expect_identical(
    lapply(as.list(fused$transformed$wide_raw), c),
    lapply(as.list(staged$wide_raw), c)
  )
  testthat::expect_identical(
    names(fused$transformed$long_raw),
    names(staged$long_raw)
  )
})

testthat::test_that("fused read+transform reports read errors like the two-stage path", {
  file_list_dt <- build_wide_workbooks()
  broken_path <- file.path(dirname(file_list_dt$file_path[1]), "broken.xlsx")
  writeLines("not an xlsx", broken_path)
  file_list_dt <- data.table::rbindlist(list(
    file_list_dt,
    data.table::data.table(
      file_path = broken_path,
      file_name = "broken.xlsx",
      yearbook = "yb_1950",
      commodity = "oats"
    )
  ))
  config <- build_test_config()

  read_result <- read_pipeline_files(file_list_dt, config, progressor = NULL)
  fused <- read_transform_pipeline_files(file_list_dt, config, progressor = NULL)

  testthat::expect_true(length(fused$errors) > 0L)
  testthat::expect_identical(fused$errors, read_result$errors)
})

testthat::test_that("fused read+transform ticks the progressor twice per file", {
  file_list_dt <- build_wide_workbooks()
  config <- build_test_config()

  tick_messages <- character(0)
  counting_progressor <- function(message, ...) {
    tick_messages <<- c(tick_messages, message)
    invisible(NULL)
  }

  read_transform_pipeline_files(
    file_list_dt,
    config,
    progressor = counting_progressor
  )

  testthat::expect_length(tick_messages, 2L * nrow(file_list_dt))
})

testthat::test_that("fused read+transform keeps empty-input contract shapes", {
  config <- build_test_config()
  empty_file_list <- data.table::data.table(
    file_path = character(0),
    file_name = character(0),
    yearbook = character(0),
    commodity = character(0)
  )

  fused <- read_transform_pipeline_files(empty_file_list, config)

  testthat::expect_identical(fused$errors, character(0))
  testthat::expect_true(data.table::is.data.table(fused$transformed$wide_raw))
  testthat::expect_true(data.table::is.data.table(fused$transformed$long_raw))
  testthat::expect_identical(nrow(fused$transformed$long_raw), 0L)
})
