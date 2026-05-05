options(
  whep.run_export_pipeline.auto = FALSE
)

source(here::here("r", "0-general_pipeline", "02-helpers", "02-assertions.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-time-formatting.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-string-normalization.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-numeric-coercion.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-token-extraction.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-data-table.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-export-validation.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-config-accessors.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-progress.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-sorting.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-environment.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-checkpoints.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-data-cleaning.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-io-cache.R"), echo = FALSE)
source(
  here::here("r", "3-export_pipeline", "30-export_data.R"),
  echo = FALSE
)
source(
  here::here("r", "3-export_pipeline", "31-export_lists.R"),
  echo = FALSE
)

build_export_test_config <- function() {
  list(
    paths = list(
      data = list(
        export = list(
          processed = file.path("data", "3-export", "processed_data"),
          lists = file.path("data", "3-export", "lists")
        )
      )
    )
  )
}

testthat::test_that("collect_layer_tables_for_export auto-detects supported layers", {
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

testthat::test_that("build export paths follow required naming conventions", {
  config <- build_export_test_config()

  processed_path <- build_processed_export_path(config, "dataset_harmonize")
  column_lists_path <- build_column_lists_export_path(config, "country")

  testthat::expect_match(
    basename(processed_path),
    "^dataset_harmonize\\.xlsx$"
  )
  testthat::expect_match(
    basename(column_lists_path),
    "^unique_country_list\\.xlsx$"
  )
})


testthat::test_that("collect_layer_tables_for_export rejects legacy names and drops post_processed", {
  env <- new.env(parent = emptyenv())
  env$whep_data_raw <- data.frame(a = 1:2)
  env$whep_data_harmonize <- data.frame(a = 1:2)
  env$whep_data_clean <- data.frame(a = 1:2)
  env$whep_data_harmonize <- data.frame(a = 1:2)
  env$whep_data_standardize <- data.frame(a = 1:2)
  env$whep_data_post_processed <- data.frame(a = 1:2)

  layer_tables <- collect_layer_tables_for_export(
    data_objects = NULL,
    env = env
  )

  testthat::expect_setequal(
    names(layer_tables),
    c("whep_data_raw", "whep_data_harmonize")
  )
  testthat::expect_false("whep_data_post_processed" %in% names(layer_tables))
  testthat::expect_false("whep_data_clean" %in% names(layer_tables))
  testthat::expect_false("whep_data_harmonize" %in% names(layer_tables))
  testthat::expect_false("whep_data_standardize" %in% names(layer_tables))
})

testthat::test_that("build_layer_tables_by_sheet enforces fixed sheet keys", {
  layer_tables <- list(
    whep_data_raw = data.frame(country = c("a", "b")),
    whep_data_harmonize = data.frame(country = c("a", "c"))
  )

  by_sheet <- build_layer_tables_by_sheet(layer_tables)

  testthat::expect_identical(names(by_sheet), c("raw", "clean", "harmonize"))
  testthat::expect_true(nrow(by_sheet$clean) == 0)
})
