# test_helper.R
# shared test utilities and fixtures for the WHEP pipeline test suite
#
# this file must be sourced before running any test file. it:
# 1. disables all auto-run options to prevent side effects
# 2. sources the general pipeline scripts (setup, helpers)
# 3. provides shared fixture builders used across test files

options(
  whep.run_pipeline.auto = FALSE,
  whep.run_general_pipeline.auto = FALSE,
  whep.run_import_pipeline.auto = FALSE,
  whep.run_postpro_pipeline.auto = FALSE,
  whep.run_export_pipeline.auto = FALSE,
  whep.checkpointing.enabled = FALSE
)

source(
  here::here("r", "0-general_pipeline", "01-setup", "01-constants.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "01-setup", "01-config.R"),
  echo = FALSE
)
source(
  here::here("r", "0-general_pipeline", "01-setup", "01-directories.R"),
  echo = FALSE
)

# explicit helper modules
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


# --- shared fixture builders ------------------------------------------------

#' Build a temporary test directory and return its path.
#' The directory is created and will be clean up when the test finishes.
build_temp_dir <- function(pattern = "whep-test-") {
  dir_path <- tempfile(pattern)
  dir.create(dir_path, recursive = TRUE)
  return(dir_path)
}

#' Build a minimal pipeline config pointing at temporary directories.
build_test_config <- function(root_dir = NULL) {
  if (is.null(root_dir)) {
    root_dir <- build_temp_dir("whep-config-")
  }

  constants <- get_pipeline_constants()

  raw_dir <- file.path(root_dir, "data", "1-import", "10-raw_import")
  cleaning_dir <- file.path(root_dir, "data", "1-import", "11-clean_import")
  standardization_dir <- file.path(
    root_dir,
    "data",
    "1-import",
    "12-standardize_import"
  )
  harmonization_dir <- file.path(
    root_dir,
    "data",
    "1-import",
    "13-harmonize_import"
  )
  processed_dir <- file.path(root_dir, "data", "3-export", "processed_data")
  lists_dir <- file.path(root_dir, "data", "3-export", "lists")
  audit_root_dir <- file.path(root_dir, "data", "2-postpro")
  audit_dir <- file.path(
    audit_root_dir,
    constants$postpro$audit_dir_name
  )
  diagnostics_dir <- file.path(
    audit_root_dir,
    constants$postpro$diagnostics_dir_name
  )
  templates_dir <- file.path(
    audit_root_dir,
    constants$postpro$templates_dir_name
  )
  runtime_cache_dir <- file.path(
    audit_root_dir,
    constants$postpro$runtime_cache_dir_name
  )

  dirs <- c(
    raw_dir,
    cleaning_dir,
    standardization_dir,
    harmonization_dir,
    processed_dir,
    lists_dir,
    audit_root_dir,
    audit_dir,
    diagnostics_dir,
    templates_dir,
    runtime_cache_dir
  )
  for (d in dirs) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }

  list(
    project_root = root_dir,
    paths = list(
      data = list(
        import = list(
          raw = raw_dir,
          cleaning = cleaning_dir,
          standardization = standardization_dir,
          harmonization = harmonization_dir
        ),
        export = list(
          processed = processed_dir,
          lists = lists_dir
        ),
        audit = list(
          audit_root_dir = audit_root_dir,
          audit_dir = audit_dir,
          diagnostics_dir = diagnostics_dir,
          templates_dir = templates_dir,
          runtime_cache_dir = runtime_cache_dir,
          audit_file_name = paste0(
            constants$dataset_default_name,
            constants$postpro$data_validation_audit_suffix
          ),
          audit_file_path = file.path(
            audit_dir,
            paste0(
              constants$dataset_default_name,
              constants$postpro$data_validation_audit_suffix
            )
          )
        )
      )
    ),
    column_required = c("continent", "country"),
    column_id = c(
      "hemisphere",
      "commodity",
      "variable",
      "unit",
      "hemisphere",
      "continent",
      "country",
      "footnotes"
    ),
    column_order = c(
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
    ),
    defaults = list(notes_value = NA_character_),
    messages = list(show_missing_commodity_metadata_warning = FALSE),
    export_config = list(
      data_suffix = ".xlsx",
      list_suffix = "_list.xlsx",
      lists_to_export = c(
        "hemisphere",
        "continent",
        "country",
        "commodity",
        "variable",
        "unit",
        "notes",
        "footnotes"
      ),
      layer_suffixes = c("_raw", "_clean", "_normalize", "_harmonize"),
      export_layers = c("harmonize"),
      styles = list(
        error_highlight = list(fontColour = "#9C0006", bgFill = "#FFC7CE")
      )
    )
  )
}

#' Create a minimal test Excel file with the given data.
#' Returns the path to the created file.
create_test_xlsx <- function(data, file_path, sheet_name = "Sheet1") {
  dir.create(dirname(file_path), recursive = TRUE, showWarnings = FALSE)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, sheet_name)
  openxlsx::writeData(wb, sheet_name, data)
  openxlsx::saveWorkbook(wb, file_path, overwrite = TRUE)
  return(file_path)
}

#' Build a sample long-format data.table for testing transformations.
build_sample_long_dt <- function(n_rows = 4L) {
  data.table::data.table(
    continent = rep(c("Asia", "Europe"), length.out = n_rows),
    country = rep(c("Japan", "France"), length.out = n_rows),
    commodity = rep("wheat", n_rows),
    variable = rep("commodityion", n_rows),
    unit = rep("tonnes", n_rows),
    year = as.character(2020L + seq_len(n_rows) - 1L),
    value = as.character(seq_len(n_rows) * 100L),
    notes = rep(NA_character_, n_rows),
    footnotes = rep(NA_character_, n_rows),
    yearbook = rep("yb_2024", n_rows),
    document = rep("test_file.xlsx", n_rows)
  )
}
