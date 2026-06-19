# Extracted from test_setup_directory_creation_contracts.R:76

# prequel ----------------------------------------------------------------------
options(
  whep.run_general_pipeline.auto = FALSE
)
source(here::here("r", "0-general_pipeline", "01-setup", "01-constants.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "01-setup", "01-config.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "01-setup", "01-directories.R"), echo = FALSE)
build_temp_test_paths <- function(root_name) {
  root_dir <- file.path(tempdir(), root_name)
  unlink(root_dir, recursive = TRUE, force = TRUE)

  return(root_dir)
}

# test -------------------------------------------------------------------------
base_dir <- build_temp_test_paths("whep_directory_contracts_audit")
paths <- list(
    data = list(
      import = list(
        raw = file.path(base_dir, "import", "raw")
      ),
      audit = list(
        audit_root_dir = file.path(base_dir, "audit"),
        audit_file_path = file.path(base_dir, "audit", "dataset", "audit.xlsx")
      )
    )
  )
created_directories <- create_required_directories(paths)
testthat::expect_true(dir.exists(file.path(base_dir, "import", "raw")))
testthat::expect_false(dir.exists(file.path(base_dir, "audit")))
