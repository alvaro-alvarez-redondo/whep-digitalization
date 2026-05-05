# script: post-processing diagnostics
# description: consumes structured audit metadata and writes deterministic
# post-processing diagnostics outputs.

#' @title Collect post-processing preflight checks
#' @description Runs deterministic preflight checks for rule directories,
#' supported filename patterns, and expected input columns.
#' @param config Named configuration list.
#' @param dataset_columns Character vector of input dataset columns.
#' @param expected_columns Character vector of required columns for current run.
#' @return Named list with `passed`, `issues`, and `checks`.
#' @importFrom checkmate assert_list assert_character
#' @importFrom fs dir_exists dir_ls
collect_postpro_preflight <- function(
  config,
  dataset_columns,
  expected_columns = c("unit", "value", "commodity")
) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_character(dataset_columns, any.missing = FALSE)
  checkmate::assert_character(
    expected_columns,
    any.missing = FALSE,
    min.len = 1
  )

  cleaning_dir <- config$paths$data$import$cleaning
  harmonization_dir <- config$paths$data$import$harmonization
  audit_paths <- get_postpro_output_paths(config)

  checks <- list(
    cleaning_dir_exists = fs::dir_exists(cleaning_dir),
    harmonize_dir_exists = fs::dir_exists(harmonization_dir),
    templates_dir_exists = fs::dir_exists(audit_paths$templates_dir),
    diagnostics_dir_exists = fs::dir_exists(audit_paths$diagnostics_dir)
  )

  issues <- character(0)

  if (!checks$cleaning_dir_exists) {
    issues <- c(issues, "[clean stage] missing 11-clean_import directory")
  }

  if (!checks$harmonize_dir_exists) {
    issues <- c(
      issues,
      "[harmonize stage] missing 13-harmonize_import directory"
    )
  }

  if (!checks$templates_dir_exists) {
    issues <- c(issues, "[postpro root] missing templates directory")
  }

  if (!checks$diagnostics_dir_exists) {
    issues <- c(issues, "[postpro root] missing diagnostics directory")
  }

  cleaning_files <- if (checks$cleaning_dir_exists) {
    fs::dir_ls(cleaning_dir, regexp = "\\.(xlsx|xls|csv)$", type = "file")
  } else {
    character(0)
  }

  harmonization_files <- if (checks$harmonize_dir_exists) {
    fs::dir_ls(harmonization_dir, regexp = "\\.(xlsx|xls|csv)$", type = "file")
  } else {
    character(0)
  }

  checks$cleaning_pattern_ok <- all(grepl(
    "^clean_.*\\.(xlsx|xls|csv)$",
    basename(cleaning_files)
  ))
  checks$harmonize_pattern_ok <- all(grepl(
    "^harmonize_.*\\.(xlsx|xls|csv)$",
    basename(harmonization_files)
  ))

  if (!checks$cleaning_pattern_ok) {
    issues <- c(
      issues,
      "[clean stage] invalid 11-clean_import file naming pattern (expected prefix: clean_)"
    )
  }

  if (!checks$harmonize_pattern_ok) {
    issues <- c(
      issues,
      "[harmonize stage] invalid 13-harmonize_import file naming pattern (expected prefix: harmonize_)"
    )
  }

  has_expected_columns <- all(expected_columns %in% dataset_columns)
  checks$has_expected_columns <- has_expected_columns

  if (!has_expected_columns) {
    issues <- c(
      issues,
      paste0(
        "[run_postpro_pipeline] missing expected columns: ",
        paste(setdiff(expected_columns, dataset_columns), collapse = ", ")
      )
    )
  }

  return(list(
    passed = length(issues) == 0,
    issues = issues,
    checks = checks
  ))
}

#' @title Assert post-processing preflight checks
#' @description Aborts execution with deterministic messages when preflight fails.
#' @param preflight_result List from `collect_postpro_preflight()`.
#' @return Invisibly returns `TRUE`.
#' @importFrom checkmate assert_list assert_flag assert_character
assert_postpro_preflight <- function(preflight_result) {
  checkmate::assert_list(preflight_result, min.len = 1)
  checkmate::assert_flag(preflight_result$passed)
  checkmate::assert_character(preflight_result$issues, any.missing = FALSE)

  if (!isTRUE(preflight_result$passed)) {
    cli::cli_abort(c(
      "Post-processing preflight checks failed.",
      preflight_result$issues
    ))
  }

  return(invisible(TRUE))
}

#' @title Summarize clean/harmonize audit records
#' @description Normalizes audit records into a row-level mirror of the clean or
#' harmonize rule dictionary, preserving loop and affected-row detail.
#' @param audit_dt Audit data.table from a post-processing stage.
#' @param stage_name Character scalar stage label for the summary.
#' @return `data.table` with one row per audit record.
#' @importFrom data.table as.data.table data.table
