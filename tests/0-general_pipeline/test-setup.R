# tests/0-general_pipeline/test-setup.R
# unit tests for R/0-general_pipeline/01-setup/ modules

source(here::here("tests", "test_helper.R"), echo = FALSE)


# --- get_pipeline_constants --------------------------------------------------

testthat::test_that("get_pipeline_constants returns a named list with required keys", {
  constants <- get_pipeline_constants()

  testthat::expect_true(is.list(constants))
  testthat::expect_true("dataset_default_name" %in% names(constants))
  testthat::expect_true("timestamp_format_utc" %in% names(constants))
  testthat::expect_true("na_placeholder" %in% names(constants))
  testthat::expect_true("na_match_key" %in% names(constants))
  testthat::expect_true("auto_run_options" %in% names(constants))
  testthat::expect_true("object_names" %in% names(constants))
  testthat::expect_true("sorting" %in% names(constants))
  testthat::expect_identical(
    constants$sorting$stage_row_order,
    c(
      "hemisphere",
      "continent",
      "country",
      "commodity",
      "variable",
      "unit",
      "year",
      "value",
      "notes",
      "footnotes",
      "yearbook",
      "document"
    )
  )
  testthat::expect_false(constants$postpro$runtime_cache$enabled)
  testthat::expect_false(
    constants$postpro$schema_validation_cache$enabled
  )
})

testthat::test_that("get_pipeline_constants returns identical result on repeated calls", {
  first <- get_pipeline_constants()
  second <- get_pipeline_constants()

  testthat::expect_identical(first, second)
})


# --- load_pipeline_config ----------------------------------------------------

testthat::test_that("load_pipeline_config builds a valid config object", {
  config <- load_pipeline_config()

  testthat::expect_true(is.list(config))
  testthat::expect_true("paths" %in% names(config))
  testthat::expect_true("column_order" %in% names(config))
  testthat::expect_true("export_config" %in% names(config))
  testthat::expect_true("project_root" %in% names(config))
  testthat::expect_true("postpro" %in% names(config))
  testthat::expect_true("sorting" %in% names(config))
  testthat::expect_identical(
    config$sorting$stage_row_order,
    get_pipeline_constants()$sorting$stage_row_order
  )
  testthat::expect_true("multi_pass" %in% names(config$postpro))
})

testthat::test_that("load_pipeline_config accepts custom dataset_name", {
  config <- load_pipeline_config(dataset_name = "custom_dataset")

  testthat::expect_true(grepl(
    "custom_dataset",
    config$paths$data$audit$audit_file_name
  ))
})


# --- resolve_audit_root_dir --------------------------------------------------

testthat::test_that("resolve_audit_root_dir returns NULL for missing paths", {
  testthat::expect_null(resolve_audit_root_dir(list(export = list())))
  testthat::expect_null(resolve_audit_root_dir(list()))
})

testthat::test_that("resolve_audit_root_dir returns configured value", {
  paths <- list(data = list(audit = list(audit_root_dir = "/tmp/audit")))
  result <- resolve_audit_root_dir(paths)

  testthat::expect_identical(result, "/tmp/audit")
})


# --- ensure_directories_exist ------------------------------------------------

testthat::test_that("ensure_directories_exist creates directories in sorted order", {
  base_dir <- build_temp_dir("whep-dir-sorted-")
  dirs <- c(
    file.path(base_dir, "z_dir"),
    file.path(base_dir, "a_dir"),
    file.path(base_dir, "a_dir")
  )

  created <- ensure_directories_exist(dirs, recurse = TRUE)

  testthat::expect_identical(created, sort(unique(dirs)))
  testthat::expect_true(all(vapply(created, dir.exists, logical(1))))
})

testthat::test_that("ensure_directories_exist handles empty input", {
  created <- ensure_directories_exist(character(0), recurse = TRUE)

  testthat::expect_identical(created, character(0))
})


# --- delete_directory_if_exists ----------------------------------------------

testthat::test_that("delete_directory_if_exists removes existing directory", {
  dir_path <- build_temp_dir("whep-delete-")
  testthat::expect_true(dir.exists(dir_path))

  deleted <- delete_directory_if_exists(dir_path)

  testthat::expect_true(deleted)
  testthat::expect_false(dir.exists(dir_path))
})

testthat::test_that("delete_directory_if_exists returns FALSE for non-existent directory", {
  deleted <- delete_directory_if_exists(file.path(tempdir(), "nonexistent_dir"))

  testthat::expect_false(deleted)
})


# --- create_required_directories ---------------------------------------------

testthat::test_that("create_required_directories creates nested structures", {
  base_dir <- build_temp_dir("whep-required-dirs-")
  paths <- list(
    export = list(
      lists = file.path(base_dir, "lists"),
      workbook = file.path(base_dir, "reports", "summary.xlsx")
    )
  )

  created <- create_required_directories(paths)

  testthat::expect_true(dir.exists(file.path(base_dir, "lists")))
  testthat::expect_true(dir.exists(file.path(base_dir, "reports")))
})

testthat::test_that("create_required_directories allows audit descendants", {
  base_dir <- build_temp_dir("whep-required-audit-")
  paths <- list(
    data = list(
      import = list(raw = file.path(base_dir, "import", "raw")),
      audit = list(
        audit_root_dir = file.path(base_dir, "audit"),
        audit_file_path = file.path(base_dir, "audit", "dataset", "audit.xlsx")
      )
    )
  )

  created <- create_required_directories(paths)

  testthat::expect_true(dir.exists(file.path(base_dir, "import", "raw")))
  testthat::expect_true(dir.exists(file.path(base_dir, "audit")))
  testthat::expect_true(dir.exists(file.path(base_dir, "audit", "dataset")))
})


# --- hemisphere column contract -----------------------------------------------

testthat::test_that("column_order includes hemisphere before continent", {
  config <- load_pipeline_config()

  col_order <- config$column_order
  idx_hemi <- which(col_order == "hemisphere")
  idx_cont <- which(col_order == "continent")

  testthat::expect_true(length(idx_hemi) == 1L)
  testthat::expect_true(idx_hemi < idx_cont)
})

testthat::test_that("fixed_export_columns includes hemisphere", {
  config <- load_pipeline_config()

  testthat::expect_true("hemisphere" %in% config$export_config$lists_to_export)
})

testthat::test_that("audit_columns does not include hemisphere", {
  config <- load_pipeline_config()

  testthat::expect_false("hemisphere" %in% config$audit_columns)
})
