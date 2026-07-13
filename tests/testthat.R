# test runner entry point
# sources the shared helper, then runs all test directories
source(here::here("tests", "test_helper.R"), echo = FALSE)

# run tests in the new structure (mirroring R/ directory)
test_dirs <- c(
  here::here("tests", "0-general_pipeline"),
  here::here("tests", "1-import_pipeline"),
  here::here("tests", "2-postpro_pipeline"),
  here::here("tests", "3-export_pipeline")
)

for (test_dir in test_dirs) {
  if (
    dir.exists(test_dir) && length(list.files(test_dir, pattern = "^test-")) > 0
  ) {
    testthat::test_dir(test_dir, reporter = "summary")
  }
}

# also run tests in tests/testthat/R/ if present
additional_dir <- here::here("tests", "testthat", "r")
if (
  dir.exists(additional_dir) &&
    length(list.files(additional_dir, pattern = "^test_")) > 0
) {
  testthat::test_dir(additional_dir, reporter = "summary")
}
