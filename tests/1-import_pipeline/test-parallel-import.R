# tests/1-import_pipeline/test-parallel-import.R
# Opt-in import parallelism: flag resolution + parallel/sequential output parity.

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
  "13-output/13-validate.R",
  "13-output/13-output.R"
)
purrr::walk(import_scripts, \(script_name) {
  source(here::here("r", "1-import_pipeline", script_name), echo = FALSE)
})
source(here::here("r", "1-import_pipeline", "run_import_pipeline.R"), echo = FALSE)


# --- resolve_import_parallel_workers ----------------------------------------

testthat::test_that("resolve_import_parallel_workers defaults to sequential (1)", {
  config <- build_test_config()
  testthat::expect_identical(resolve_import_parallel_workers(config), 1L)
})

testthat::test_that("resolve_import_parallel_workers reads config$performance", {
  config <- build_test_config()
  config$performance <- list(import_parallel_workers = 3L)
  testthat::expect_identical(resolve_import_parallel_workers(config), 3L)
})

testthat::test_that("whep.import.parallel_workers option overrides config", {
  config <- build_test_config()
  config$performance <- list(import_parallel_workers = 3L)
  old <- options(whep.import.parallel_workers = 5L)
  on.exit(options(old), add = TRUE)
  testthat::expect_identical(resolve_import_parallel_workers(config), 5L)
})

testthat::test_that("invalid worker counts fall back to sequential (1)", {
  config <- build_test_config()
  old <- options(whep.import.parallel_workers = "not-a-number")
  on.exit(options(old), add = TRUE)
  testthat::expect_identical(resolve_import_parallel_workers(config), 1L)

  config$performance <- list(import_parallel_workers = 0L)
  options(whep.import.parallel_workers = NULL)
  testthat::expect_identical(resolve_import_parallel_workers(config), 1L)
})


# --- parallel vs sequential output parity -----------------------------------

testthat::test_that("parallel import yields identical output to sequential", {
  config <- build_test_config()
  # Force >1 batch with few files so the parallel read path is exercised.
  config$performance <- list(import_workbook_batch_size = 1L)
  # The minimal test config omits this default that the real config carries;
  # transform needs it when a filename yields no commodity token.
  config$defaults$unknown_commodity <-
    get_pipeline_constants()$defaults$unknown_commodity

  raw_dir <- config$paths$data$import$raw
  wide <- data.frame(
    continent = c("Asia", "Europe", "Africa"),
    polity = c("Japan", "France", "Egypt"),
    `2020` = c("10", "20", "30"),
    `2021` = c("40", "50", "60"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  for (i in seq_len(4L)) {
    create_test_xlsx(
      wide,
      file.path(raw_dir, sprintf("test_yearbook_2020_commodity%d.xlsx", i))
    )
  }

  start_plan <- future::plan(future::sequential)
  on.exit(future::plan(start_plan), add = TRUE)

  normalize <- function(dt) {
    d <- data.table::as.data.table(dt)
    data.table::setorderv(d, names(d))
    as.data.frame(d, stringsAsFactors = FALSE)
  }

  # sequential (default flag = 1 worker)
  sequential_result <- run_import_pipeline(config)

  # parallel via the opt-in option. A genuine output mismatch is asserted below
  # via expect_identical; only an environmental inability to start multisession
  # workers (worker/connection/socket startup) skips, so this never turns a
  # CI-environment limitation into a suite failure.
  old <- options(whep.import.parallel_workers = 2L)
  on.exit(options(old), add = TRUE)
  parallel_result <- tryCatch(
    run_import_pipeline(config),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl(
        "worker|connection|port|socket|multisession|cluster",
        msg,
        ignore.case = TRUE
      )) {
        testthat::skip(paste("multisession workers unavailable:", msg))
      }
      stop(e)
    }
  )

  testthat::expect_false(inherits(future::plan(), "multisession")) # plan restored
  testthat::expect_gt(nrow(sequential_result$data), 0L)
  testthat::expect_identical(
    normalize(sequential_result$data),
    normalize(parallel_result$data)
  )
})
