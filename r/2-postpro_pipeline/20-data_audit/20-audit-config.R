# script: 30-data_audit.r
# description: validate consolidated pipeline data, isolate invalid records,
# and export deterministic audit artifacts.

#' @title prepare audit output directory
#' @description safely remove previous audit folder if it exists.
#' when deletion fails due to permissions or file locks, keeps the existing
#' folder and continues with an informational message so the pipeline can still write outputs.
#' @param audit_root_dir character scalar path to the audit output folder.
#' @return invisible logical scalar: TRUE if folder existed and was deleted,
#' FALSE when folder did not exist or could not be removed.
#' @examples
#' audit_root_dir <- fs::path(tempdir(), "audit")
#' fs::dir_create(audit_root_dir)
#' prepare_audit_root(audit_root_dir)
#' @export
prepare_audit_root <- function(audit_root_dir) {
  assert_or_abort(checkmate::check_string(audit_root_dir, min.chars = 1))

  deleted <- delete_directory_if_exists(
    directory = audit_root_dir,
    tolerate_permission_errors = TRUE
  )

  if (!deleted && fs::dir_exists(audit_root_dir)) {
    cli::cli_alert_info(
      "audit root cleanup skipped due to locked/permission-protected files; continuing with existing folder {.path {audit_root_dir}}."
    )
  }

  return(invisible(deleted))
}

#' @title empty audit findings data table
#' @description create a standardized empty audit findings data table.
#' @return data.table with predefined audit columns.
#' @examples
#' empty_audit_findings_dt()
#' @export
empty_audit_findings_dt <- function() {
  return(data.table::data.table(
    row_index = integer(),
    audit_column = character(),
    audit_type = character(),
    audit_message = character()
  ))
}

#' @title load audit configuration
#' @description validate required audit configuration fields used by the export audit workflow.
#' @param config named list containing required configuration elements.
#' @return invisible TRUE when validation succeeds.
#' @examples
#' load_audit_config(config)
#' @export
load_audit_config <- function(config) {
  assert_or_abort(checkmate::check_list(
    config,
    min.len = 1,
    any.missing = FALSE
  ))
  assert_or_abort(checkmate::check_character(
    config$column_order,
    min.len = 1,
    any.missing = FALSE
  ))
  assert_or_abort(checkmate::check_character(
    config$audit_columns,
    min.len = 1,
    any.missing = FALSE
  ))

  if (!is.null(config$audit_columns_by_type)) {
    assert_or_abort(checkmate::check_list(
      config$audit_columns_by_type,
      min.len = 1,
      any.missing = FALSE
    ))

    audit_columns_valid <- vapply(
      config$audit_columns_by_type,
      function(audit_columns) {
        isTRUE(checkmate::check_character(
          audit_columns,
          min.len = 1,
          any.missing = FALSE
        ))
      },
      logical(1)
    )

    if (!all(audit_columns_valid)) {
      cli::cli_abort(
        "all elements in {.arg config$audit_columns_by_type} must be non-empty character vectors"
      )
    }
  }

  assert_or_abort(checkmate::check_string(
    config$paths$data$import$raw,
    min.chars = 1
  ))
  assert_or_abort(checkmate::check_string(
    config$paths$data$audit$audit_dir,
    min.chars = 1
  ))

  return(invisible(TRUE))
}

#' @title resolve audit output paths
#' @description compute audit output paths without creating directories.
#' @param audit_root_dir character scalar audit output directory.
#' @param audit_file_name character scalar excel file name.
#' @return named list with `audit_root_dir` and `audit_file_path`.
#' @examples
#' resolve_audit_output_paths("data/2-postpro/audit", "audit.xlsx")
#' @export
resolve_audit_output_paths <- function(
  audit_root_dir,
  audit_file_name
) {
  assert_or_abort(checkmate::check_string(audit_root_dir, min.chars = 1))
  assert_or_abort(checkmate::check_string(audit_file_name, min.chars = 1))

  return(list(
    audit_root_dir = audit_root_dir,
    audit_file_path = fs::path(audit_root_dir, audit_file_name)
  ))
}

#' @title audit non-empty character values
#' @description validate that values are non-missing and non-empty.
#' @param dataset_dt data frame.
#' @param column_name character scalar.
#' @return data.table of findings.
#' @examples
#' dataset_dt <- data.frame(document = c("ok.xlsx", ""), stringsAsFactors = FALSE)
#' audit_character_non_empty(dataset_dt, "document")
#' @export
