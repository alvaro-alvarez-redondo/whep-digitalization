options(
  whep.run_postpro_pipeline.auto = FALSE
)

source(here::here("tests", "test_helper.R"), echo = FALSE)

source(here::here("r", "2-postpro_pipeline", "run_postpro_pipeline.R"), echo = FALSE)

testthat::test_that("generate_postpro_rule_templates writes clean and harmonize templates", {
  root_dir <- tempfile("whep-template-generation-")
  dir.create(root_dir, recursive = TRUE)

  audit_root_dir <- file.path(root_dir, "data", "2-postpro")

  config <- list(
    paths = list(
      data = list(
        audit = list(
          audit_root_dir = audit_root_dir
        )
      )
    )
  )

  template_paths <- generate_postpro_rule_templates(
    config = config,
    overwrite = TRUE
  )

  testthat::expect_identical(names(template_paths), "clean_harmonize_template")
  testthat::expect_true(all(file.exists(unname(template_paths))))

  testthat::expect_match(
    basename(template_paths[["clean_harmonize_template"]]),
    "^clean_harmonize_template\\.xlsx$"
  )
})
