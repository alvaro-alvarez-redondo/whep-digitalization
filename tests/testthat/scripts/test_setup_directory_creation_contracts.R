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

testthat::test_that("resolve_audit_root_dir returns configured scalar or NULL", {
  testthat::expect_null(resolve_audit_root_dir(list(export = list())))

  audit_root <- resolve_audit_root_dir(
    list(data = list(audit = list(audit_root_dir = file.path("tmp", "audit"))))
  )

  testthat::expect_identical(audit_root, file.path("tmp", "audit"))
})

testthat::test_that("create_required_directories handles generic path lists without audit structure", {
  base_dir <- build_temp_test_paths("whep_directory_contracts_generic")
  paths <- list(
    export = list(
      lists = file.path(base_dir, "lists"),
      workbook = file.path(base_dir, "reports", "summary.xlsx")
    )
  )

  created_directories <- create_required_directories(paths)

  normalize_created <- vapply(
    created_directories,
    function(path_i) {
      normalizePath(path_i, winslash = "/", mustWork = FALSE)
    },
    character(1)
  )
  normalize_expected <- vapply(
    c(file.path(base_dir, "lists"), file.path(base_dir, "reports")),
    function(path_i) {
      normalizePath(path_i, winslash = "/", mustWork = FALSE)
    },
    character(1)
  )

  testthat::expect_true(dir.exists(file.path(base_dir, "lists")))
  testthat::expect_true(dir.exists(file.path(base_dir, "reports")))
  testthat::expect_true(
    all(normalize_expected %in% normalize_created)
  )
})

testthat::test_that("create_required_directories excludes audit root tree when configured", {
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
  testthat::expect_false(any(startsWith(
    created_directories,
    file.path(base_dir, "audit")
  )))
})


testthat::test_that("ensure_directories_exist creates sorted deterministic directories", {
  base_dir <- build_temp_test_paths("whep_ensure_directories")
  directories <- c(
    file.path(base_dir, "z_dir"),
    file.path(base_dir, "a_dir"),
    file.path(base_dir, "a_dir")
  )

  created <- ensure_directories_exist(directories, recurse = TRUE)

  testthat::expect_identical(created, sort(unique(directories)))
  testthat::expect_true(all(vapply(created, dir.exists, logical(1))))
})

testthat::test_that("delete_directory_if_exists removes existing directory", {
  base_dir <- build_temp_test_paths("whep_delete_directories")
  ensure_directories_exist(base_dir, recurse = TRUE)

  deleted <- delete_directory_if_exists(base_dir)

  testthat::expect_true(deleted)
  testthat::expect_false(dir.exists(base_dir))
})
