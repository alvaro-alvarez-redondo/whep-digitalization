# tests/3-export_pipeline/test-export-data.R
# unit tests for R/3-export_pipeline/30-processed_data/*.R

source(here::here("tests", "test_helper.R"), echo = FALSE)
export_scripts <- c(
  "30-processed_data/01-build-processed-export-path.R",
  "30-processed_data/02-collect-layer-tables.R",
  "30-processed_data/03-write-processed-table-fast.R",
  "30-processed_data/04-export-processed-data.R",
  "31-lists/01-sheet-order-and-infer.R",
  "31-lists/02-build-path-and-unique-values.R",
  "31-lists/03-resolve-and-compare.R",
  "31-lists/04-cache-and-write.R"
)

lapply(export_scripts, function(script_name) {
  source(here::here("r", "3-export_pipeline", script_name), echo = FALSE)
})


# --- collect_layer_tables_for_export -----------------------------------------

testthat::test_that("collect_layer_tables_for_export auto-detects strict layers", {
  env <- new.env(parent = emptyenv())
  env$demo_raw <- data.frame(a = 1:2)
  env$demo_clean <- data.frame(a = 1:2)
  env$demo_other <- data.frame(a = 1:2)
  env$demo_wide_raw <- data.frame(a = 1:2)

  layer_tables <- collect_layer_tables_for_export(
    data_objects = NULL,
    env = env
  )

  testthat::expect_setequal(names(layer_tables), c("demo_clean", "demo_raw"))
  testthat::expect_false("demo_wide_raw" %in% names(layer_tables))
})

testthat::test_that("collect_layer_tables_for_export rejects unsupported suffixes", {
  env <- new.env(parent = emptyenv())
  env$whep_data_clean <- data.frame(a = 1:2)
  env$whep_data_harmonize <- data.frame(a = 1:2)
  env$whep_data_standardize <- data.frame(a = 1:2)

  layer_tables <- collect_layer_tables_for_export(
    data_objects = NULL,
    env = env
  )

  testthat::expect_setequal(
    names(layer_tables),
    c("whep_data_clean", "whep_data_harmonize")
  )
  testthat::expect_false("whep_data_standardize" %in% names(layer_tables))
})

testthat::test_that("collect_layer_tables_for_export accepts explicit data_objects", {
  data_objects <- list(
    test_raw = data.frame(a = 1:2),
    test_clean = data.frame(a = 1:2)
  )

  layer_tables <- collect_layer_tables_for_export(
    data_objects = data_objects,
    env = new.env(parent = emptyenv())
  )

  testthat::expect_true("test_raw" %in% names(layer_tables))
  testthat::expect_true("test_clean" %in% names(layer_tables))
})


# --- build_processed_export_path ---------------------------------------------

testthat::test_that("build_processed_export_path generates correct naming", {
  config <- build_test_config()

  path <- build_processed_export_path(config, "dataset_harmonize")

  testthat::expect_match(basename(path), "^dataset_harmonize\\.xlsx$")
})


# --- write_processed_table_fast ----------------------------------------------

testthat::test_that("write_processed_table_fast writes valid xlsx with correct content", {
  root_dir <- build_temp_dir("whep-write-table-")
  file_path <- file.path(root_dir, "output.xlsx")

  dt <- data.table::data.table(
    polity = c("Japan", "France"),
    value = c("100", "200")
  )

  write_processed_table_fast(dt, file_path)

  testthat::expect_true(file.exists(file_path))
  testthat::expect_identical(
    readxl::excel_sheets(file_path),
    "processed_data"
  )

  # verify the file can be read back with correct content
  read_back <- readxl::read_excel(file_path)
  testthat::expect_equal(nrow(read_back), 2L)
  testthat::expect_equal(colnames(read_back), c("polity", "value"))
  testthat::expect_equal(read_back$polity, c("Japan", "France"))
})

testthat::test_that("write_processed_table_fast respects overwrite flag", {
  root_dir <- build_temp_dir("whep-write-overwrite-")
  file_path <- file.path(root_dir, "output.xlsx")

  dt <- data.table::data.table(a = 1:2)
  write_processed_table_fast(dt, file_path)

  testthat::expect_error(
    write_processed_table_fast(dt, file_path, overwrite = FALSE),
    "overwrite"
  )
})


# --- export_processed_data --------------------------------------------------

testthat::test_that("export_processed_data writes workbooks only for harmonize layer by default", {
  config <- build_test_config()

  data_objects <- list(
    test_raw = data.table::data.table(
      polity = c("a", "b"),
      value = c("1", "2")
    ),
    test_clean = data.table::data.table(
      polity = c("a", "b"),
      value = c("1", "2")
    ),
    test_harmonize = data.table::data.table(
      polity = c("a", "b"),
      value = c("1", "2")
    )
  )

  paths <- export_processed_data(
    config = config,
    data_objects = data_objects,
    overwrite = TRUE,
    env = new.env(parent = emptyenv())
  )

  testthat::expect_true(is.character(paths))
  testthat::expect_equal(length(paths), 1L)
  testthat::expect_true(all(file.exists(paths)))
  testthat::expect_true("test_harmonize" %in% names(paths))
})

testthat::test_that("export_processed_data export all layers when config overrides export_layers", {
  config <- build_test_config()
  config$export_config$export_layers <- c("raw", "clean", "harmonize")

  data_objects <- list(
    test_raw = data.table::data.table(
      polity = c("a", "b"),
      value = c("1", "2")
    ),
    test_clean = data.table::data.table(
      polity = c("a", "b"),
      value = c("1", "2")
    ),
    test_harmonize = data.table::data.table(
      polity = c("a", "b"),
      value = c("1", "2")
    )
  )

  paths <- export_processed_data(
    config = config,
    data_objects = data_objects,
    overwrite = TRUE,
    env = new.env(parent = emptyenv())
  )

  testthat::expect_true(is.character(paths))
  testthat::expect_equal(length(paths), 3L)
  testthat::expect_true(all(file.exists(paths)))
  testthat::expect_true(any(grepl("raw", names(paths))))
  testthat::expect_true(any(grepl("clean", names(paths))))
  testthat::expect_true(any(grepl("harmonize", names(paths))))
})

testthat::test_that("export_processed_data errors when no matching layers for export_layers", {
  config <- build_test_config()

  data_objects <- list(
    test_raw = data.table::data.table(
      polity = c("a", "b"),
      value = c("1", "2")
    ),
    test_clean = data.table::data.table(
      polity = c("a", "b"),
      value = c("1", "2")
    )
  )

  testthat::expect_error(
    export_processed_data(
      config = config,
      data_objects = data_objects,
      overwrite = TRUE,
      env = new.env(parent = emptyenv())
    ),
    "harmonize"
  )
})
