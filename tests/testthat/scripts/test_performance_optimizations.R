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

  # project_root keeps contract-test checkpoints out of the real
  # data/.checkpoints directory.
  project_root <- tempfile("whep-ckpt-contract-")
  dir.create(project_root, recursive = TRUE)
  config <- list(
    project_root = project_root,
    paths = list(data = list(root = tempdir()))
  )
  test_data <- list(value = 42, name = "test")

  save_path <- save_pipeline_checkpoint(
    result = test_data,
    checkpoint_name = "round_trip_test",
    config = config
  )

  testthat::expect_true(is.character(save_path))
  testthat::expect_true(file.exists(save_path))
  testthat::expect_true(fs::path_has_parent(save_path, project_root))

  loaded_data <- load_pipeline_checkpoint(
    checkpoint_name = "round_trip_test",
    config = config
  )

  testthat::expect_identical(loaded_data, test_data)
})

testthat::test_that("load_pipeline_checkpoint returns NULL for missing checkpoint", {
  withr::local_options(whep.checkpointing.enabled = TRUE)

  project_root <- tempfile("whep-ckpt-contract-")
  dir.create(project_root, recursive = TRUE)
  config <- list(
    project_root = project_root,
    paths = list(data = list(root = tempdir()))
  )
  result <- load_pipeline_checkpoint(
    checkpoint_name = "nonexistent_checkpoint",
    config = config
  )

  testthat::expect_null(result)
})

testthat::test_that("clear_pipeline_checkpoints removes checkpoint directory", {
  withr::local_options(whep.checkpointing.enabled = TRUE)

  project_root <- tempfile("whep-ckpt-contract-")
  dir.create(project_root, recursive = TRUE)
  config <- list(
    project_root = project_root,
    paths = list(data = list(root = tempdir()))
  )
  test_data <- list(value = 42)

  checkpoint_dir <- fs::path(project_root, "data", ".checkpoints")

  save_pipeline_checkpoint(
    result = test_data,
    checkpoint_name = "clear_test",
    config = config
  )

  testthat::expect_true(fs::dir_exists(checkpoint_dir))

  clear_pipeline_checkpoints(config)

  testthat::expect_false(fs::dir_exists(checkpoint_dir))
})

testthat::test_that("stale checkpoint inputs force a rebuild (load returns NULL)", {
  withr::local_options(whep.checkpointing.enabled = TRUE)

  project_root <- tempfile("whep-ckpt-contract-")
  raw_dir <- file.path(project_root, "data", "1-import", "10-raw_import")
  dir.create(raw_dir, recursive = TRUE)
  config <- list(
    project_root = project_root,
    paths = list(data = list(import = list(raw = raw_dir)))
  )
  writeLines("wb1", file.path(raw_dir, "wb1.xlsx"))

  save_pipeline_checkpoint(
    result = list(data = "stale"),
    checkpoint_name = "import_pipeline",
    config = config
  )

  writeLines("wb2", file.path(raw_dir, "wb2.xlsx"))

  loaded <- load_pipeline_checkpoint(
    checkpoint_name = "import_pipeline",
    config = config
  )

  testthat::expect_null(loaded)
})
