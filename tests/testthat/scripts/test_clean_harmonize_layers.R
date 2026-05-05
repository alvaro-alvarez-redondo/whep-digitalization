options(
  whep.run_postpro_pipeline.auto = FALSE
)

source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-assertions.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-time-formatting.R"),
  echo = FALSE
)
source(
  here::here(
    "r",
    "0-general_pipeline",
    "02-helpers",
    "02-string-normalization.R"
  ),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-numeric-coercion.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-token-extraction.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-data-table.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-export-validation.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-config-accessors.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-progress.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-sorting.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-environment.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-checkpoints.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-data-cleaning.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "02-helpers", "02-io-cache.R"),
  echo = FALSE
)
source(
  here::here("r", "2-postpro_pipeline", "run_postpro_pipeline.R"),
  echo = FALSE
)

testthat::test_that("clean and harmonize layers apply deterministic rule payloads", {
  root_dir <- tempfile("whep-clean-harmonize-")
  dir.create(root_dir, recursive = TRUE)

  clean_dir <- file.path(root_dir, "data", "1-import", "11-clean_import")
  harmonize_dir <- file.path(
    root_dir,
    "data",
    "1-import",
    "13-harmonize_import"
  )
  dir.create(clean_dir, recursive = TRUE)
  dir.create(harmonize_dir, recursive = TRUE)

  clean_rules <- data.frame(
    column_source = "commodity",
    value_source_raw = "Wheat",
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram",
    stringsAsFactors = FALSE
  )

  harmonize_rules <- data.frame(
    column_source = "commodity",
    value_source_raw = "Wheat",
    column_target = "variable",
    value_target_raw = "Prod",
    value_target = "commodityion",
    stringsAsFactors = FALSE
  )

  readr::write_csv(
    clean_rules,
    file.path(clean_dir, "clean_rules_commodity.csv")
  )
  readr::write_csv(
    harmonize_rules,
    file.path(harmonize_dir, "harmonize_rules_variable.csv")
  )

  config <- list(
    paths = list(
      data = list(
        import = list(
          cleaning = clean_dir,
          harmonization = harmonize_dir
        )
      )
    )
  )

  input_dt <- data.frame(
    commodity = c("Wheat", "Rice"),
    variable = c("Prod", "Prod"),
    unit = c("kg", "kg"),
    value = c("10", "20"),
    stringsAsFactors = FALSE
  )

  clean_dt <- run_cleaning_layer_batch(
    dataset_dt = input_dt,
    config = config,
    dataset_name = "demo"
  )

  harmonize_dt <- run_harmonize_layer_batch(
    dataset_dt = clean_dt,
    config = config,
    dataset_name = "demo"
  )

  testthat::expect_equal(clean_dt$unit[[1]], "kilogram")
  testthat::expect_equal(clean_dt$unit[[2]], "kg")

  testthat::expect_equal(harmonize_dt$variable[[1]], "commodityion")
  testthat::expect_equal(harmonize_dt$variable[[2]], "Prod")

  clean_audit <- attr(clean_dt, "layer_audit")
  harmonize_audit <- attr(harmonize_dt, "layer_audit")

  testthat::expect_true(nrow(clean_audit) >= 1)
  testthat::expect_true(nrow(harmonize_audit) >= 1)
})


testthat::test_that("stage-prefixed schemas are accepted by coerce_rule_schema", {
  raw_rule_dt <- data.frame(
    clean_column_source = "commodity",
    clean_value_source_raw = "Wheat",
    clean_column_target = "unit",
    clean_value_target_raw = "kg",
    clean_value_target = "kilogram",
    stringsAsFactors = FALSE
  )

  canonical_dt <- coerce_rule_schema(
    rule_dt = raw_rule_dt,
    stage_name = "clean",
    rule_file_id = "clean_rules_stage_prefixed.xlsx"
  )

  testthat::expect_true(all(
    c(
      "column_source",
      "value_source_raw",
      "value_source",
      "column_target",
      "value_target_raw",
      "value_target"
    ) %in%
      colnames(canonical_dt)
  ))

  testthat::expect_equal(canonical_dt$value_target[[1]], "kilogram")
  testthat::expect_true("value_source" %in% colnames(canonical_dt))
  testthat::expect_true(is.na(canonical_dt$value_source[[1]]))
})


testthat::test_that("clean layer auto-creates missing rule-referenced columns", {
  root_dir <- tempfile("whep-clean-missing-cols-")
  dir.create(root_dir, recursive = TRUE)

  clean_dir <- file.path(root_dir, "data", "1-import", "11-clean_import")
  harmonize_dir <- file.path(
    root_dir,
    "data",
    "1-import",
    "13-harmonize_import"
  )
  dir.create(clean_dir, recursive = TRUE)
  dir.create(harmonize_dir, recursive = TRUE)

  clean_rules <- data.frame(
    column_source = "source_missing",
    value_source_raw = "match_me",
    column_target = "target_missing",
    value_target_raw = "before",
    value_target = "after",
    stringsAsFactors = FALSE
  )

  readr::write_csv(
    clean_rules,
    file.path(clean_dir, "clean_rules_missing_columns.csv")
  )

  config <- list(
    paths = list(
      data = list(
        import = list(
          cleaning = clean_dir,
          harmonization = harmonize_dir
        )
      )
    )
  )

  input_dt <- data.frame(
    commodity = c("Wheat", "Rice"),
    variable = c("Prod", "Prod"),
    unit = c("kg", "kg"),
    stringsAsFactors = FALSE
  )

  clean_dt <- run_cleaning_layer_batch(
    dataset_dt = input_dt,
    config = config,
    dataset_name = "demo"
  )

  testthat::expect_true("source_missing" %in% colnames(clean_dt))
  testthat::expect_true("target_missing" %in% colnames(clean_dt))
  testthat::expect_true(all(is.na(clean_dt$source_missing)))
  testthat::expect_true(all(is.na(clean_dt$target_missing)))
})


testthat::test_that("clean stage applies optional source rewrites", {
  root_dir <- tempfile("whep-clean-source-rewrite-")
  dir.create(root_dir, recursive = TRUE)

  clean_dir <- file.path(root_dir, "data", "1-import", "11-clean_import")
  harmonize_dir <- file.path(
    root_dir,
    "data",
    "1-import",
    "13-harmonize_import"
  )
  dir.create(clean_dir, recursive = TRUE)
  dir.create(harmonize_dir, recursive = TRUE)

  clean_rules <- data.frame(
    column_source = "commodity",
    value_source_raw = "Wheat",
    value_source = "Wheat clean",
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram",
    stringsAsFactors = FALSE
  )

  readr::write_csv(
    clean_rules,
    file.path(clean_dir, "clean_rules_source_rewrite.csv")
  )

  config <- list(
    paths = list(
      data = list(
        import = list(
          cleaning = clean_dir,
          harmonization = harmonize_dir
        )
      )
    )
  )

  input_dt <- data.frame(
    commodity = c("Wheat", "Rice"),
    unit = c("kg", "kg"),
    stringsAsFactors = FALSE
  )

  clean_dt <- run_cleaning_layer_batch(
    dataset_dt = input_dt,
    config = config,
    dataset_name = "demo"
  )

  testthat::expect_equal(clean_dt$commodity[[1]], "Wheat clean")
  testthat::expect_equal(clean_dt$commodity[[2]], "Rice")
  testthat::expect_equal(clean_dt$unit[[1]], "kilogram")
})


testthat::test_that("when source and target columns are identical target rewrite has precedence", {
  root_dir <- tempfile("whep-clean-same-column-")
  dir.create(root_dir, recursive = TRUE)

  clean_dir <- file.path(root_dir, "data", "1-import", "11-clean_import")
  harmonize_dir <- file.path(
    root_dir,
    "data",
    "1-import",
    "13-harmonize_import"
  )
  dir.create(clean_dir, recursive = TRUE)
  dir.create(harmonize_dir, recursive = TRUE)

  clean_rules <- data.frame(
    column_source = "commodity",
    value_source_raw = "Wheat",
    value_source = "Wheat source",
    column_target = "commodity",
    value_target_raw = "Wheat",
    value_target = "Wheat target",
    stringsAsFactors = FALSE
  )

  readr::write_csv(
    clean_rules,
    file.path(clean_dir, "clean_rules_same_column.csv")
  )

  config <- list(
    paths = list(
      data = list(
        import = list(
          cleaning = clean_dir,
          harmonization = harmonize_dir
        )
      )
    )
  )

  input_dt <- data.frame(
    commodity = c("Wheat", "Rice"),
    stringsAsFactors = FALSE
  )

  clean_dt <- run_cleaning_layer_batch(
    dataset_dt = input_dt,
    config = config,
    dataset_name = "demo"
  )

  testthat::expect_equal(clean_dt$commodity[[1]], "Wheat target")
  testthat::expect_equal(clean_dt$commodity[[2]], "Rice")
})


testthat::test_that("harmonize stage applies optional source rewrites", {
  root_dir <- tempfile("whep-harmonize-source-rewrite-")
  dir.create(root_dir, recursive = TRUE)

  clean_dir <- file.path(root_dir, "data", "1-import", "11-clean_import")
  harmonize_dir <- file.path(
    root_dir,
    "data",
    "1-import",
    "13-harmonize_import"
  )
  dir.create(clean_dir, recursive = TRUE)
  dir.create(harmonize_dir, recursive = TRUE)

  harmonize_rules <- data.frame(
    column_source = "variable",
    value_source_raw = "Prod",
    value_source = "commodityion",
    column_target = "unit",
    value_target_raw = "kg",
    value_target = "kilogram",
    stringsAsFactors = FALSE
  )

  readr::write_csv(
    harmonize_rules,
    file.path(harmonize_dir, "harmonize_rules_source_rewrite.csv")
  )

  config <- list(
    paths = list(
      data = list(
        import = list(
          cleaning = clean_dir,
          harmonization = harmonize_dir
        )
      )
    )
  )

  input_dt <- data.frame(
    variable = c("Prod", "Import"),
    unit = c("kg", "kg"),
    stringsAsFactors = FALSE
  )

  harmonize_dt <- run_harmonize_layer_batch(
    dataset_dt = input_dt,
    config = config,
    dataset_name = "demo"
  )

  testthat::expect_equal(harmonize_dt$variable[[1]], "commodityion")
  testthat::expect_equal(harmonize_dt$variable[[2]], "Import")
  testthat::expect_equal(harmonize_dt$unit[[1]], "kilogram")
})


testthat::test_that("clean stage blank source rewrite assigns NA on matched rows", {
  root_dir <- tempfile("whep-clean-source-blank-")
  dir.create(root_dir, recursive = TRUE)

  clean_dir <- file.path(root_dir, "data", "1-import", "11-clean_import")
  harmonize_dir <- file.path(
    root_dir,
    "data",
    "1-import",
    "13-harmonize_import"
  )
  dir.create(clean_dir, recursive = TRUE)
  dir.create(harmonize_dir, recursive = TRUE)

  clean_rules <- data.frame(
    column_source = "continent",
    value_source_raw = "asia",
    value_source = "",
    column_target = "commodity",
    value_target_raw = "wheat",
    value_target = "asia wheat",
    stringsAsFactors = FALSE
  )

  readr::write_csv(
    clean_rules,
    file.path(clean_dir, "clean_rules_blank_source.csv")
  )

  config <- list(
    paths = list(
      data = list(
        import = list(
          cleaning = clean_dir,
          harmonization = harmonize_dir
        )
      )
    )
  )

  input_dt <- data.frame(
    continent = c("asia", "europe"),
    commodity = c("wheat", "wheat"),
    stringsAsFactors = FALSE
  )

  clean_dt <- run_cleaning_layer_batch(
    dataset_dt = input_dt,
    config = config,
    dataset_name = "demo"
  )

  testthat::expect_true(is.na(clean_dt$continent[[1]]))
  testthat::expect_equal(clean_dt$continent[[2]], "europe")
  testthat::expect_equal(clean_dt$commodity[[1]], "asia wheat")
  testthat::expect_equal(clean_dt$commodity[[2]], "wheat")
})
