options(
  whep.run_postpro_pipeline.auto = FALSE,
  whep.run_pipeline.auto = FALSE,
  whep.checkpointing.enabled = FALSE
)

source(here::here("r", "0-general_pipeline", "01-setup", "01-constants.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "01-setup", "01-config.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "01-setup", "01-directories.R"), echo = FALSE)

# explicit helper modules
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


# --- get_pipeline_constants caching ---

testthat::test_that("get_pipeline_constants returns cached result on repeated calls", {
  first_result <- get_pipeline_constants()
  second_result <- get_pipeline_constants()

  testthat::expect_identical(first_result, second_result)
  testthat::expect_true(is.list(first_result))
  testthat::expect_true("dataset_default_name" %in% names(first_result))
  testthat::expect_true("na_placeholder" %in% names(first_result))
  testthat::expect_true("na_match_key" %in% names(first_result))
})


# --- Checkpointing functions ---

testthat::test_that("save_pipeline_checkpoint returns NULL when checkpointing is disabled", {
  options(whep.checkpointing.enabled = FALSE)

  config <- list(paths = list(data = list(root = tempdir())))
  result <- save_pipeline_checkpoint(
    result = list(a = 1),
    checkpoint_name = "test_checkpoint",
    config = config
  )

  testthat::expect_null(result)
})

testthat::test_that("load_pipeline_checkpoint returns NULL when checkpointing is disabled", {
  options(whep.checkpointing.enabled = FALSE)

  config <- list(paths = list(data = list(root = tempdir())))
  result <- load_pipeline_checkpoint(
    checkpoint_name = "test_checkpoint",
    config = config
  )

  testthat::expect_null(result)
})

testthat::test_that("save and load checkpoint round-trips data when enabled", {
  withr::local_options(whep.checkpointing.enabled = TRUE)

  config <- list(paths = list(data = list(root = tempdir())))
  test_data <- list(value = 42, name = "test")

  checkpoint_dir <- fs::path(here::here(), "data", ".checkpoints")
  withr::defer(
    if (fs::dir_exists(checkpoint_dir)) fs::dir_delete(checkpoint_dir)
  )

  save_path <- save_pipeline_checkpoint(
    result = test_data,
    checkpoint_name = "round_trip_test",
    config = config
  )

  testthat::expect_true(is.character(save_path))
  testthat::expect_true(file.exists(save_path))

  loaded_data <- load_pipeline_checkpoint(
    checkpoint_name = "round_trip_test",
    config = config
  )

  testthat::expect_identical(loaded_data, test_data)
})

testthat::test_that("load_pipeline_checkpoint returns NULL for missing checkpoint", {
  withr::local_options(whep.checkpointing.enabled = TRUE)

  config <- list(paths = list(data = list(root = tempdir())))
  result <- load_pipeline_checkpoint(
    checkpoint_name = "nonexistent_checkpoint",
    config = config
  )

  testthat::expect_null(result)
})

testthat::test_that("clear_pipeline_checkpoints removes checkpoint directory", {
  withr::local_options(whep.checkpointing.enabled = TRUE)

  config <- list(paths = list(data = list(root = tempdir())))
  test_data <- list(value = 42)

  checkpoint_dir <- fs::path(here::here(), "data", ".checkpoints")

  save_pipeline_checkpoint(
    result = test_data,
    checkpoint_name = "clear_test",
    config = config
  )

  testthat::expect_true(fs::dir_exists(checkpoint_dir))

  clear_pipeline_checkpoints(config)

  testthat::expect_false(fs::dir_exists(checkpoint_dir))
})
