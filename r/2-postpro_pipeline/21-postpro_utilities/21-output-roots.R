get_postpro_output_paths <- function(config) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(
    config$paths$data$audit$audit_root_dir,
    min.chars = 1
  )

  audit_root_dir <- config$paths$data$audit$audit_root_dir

  return(list(
    audit_root_dir = audit_root_dir,
    audit_dir = config$paths$data$audit$audit_dir,
    diagnostics_dir = config$paths$data$audit$diagnostics_dir,
    templates_dir = config$paths$data$audit$templates_dir,
    runtime_cache_dir = config$paths$data$audit$runtime_cache_dir
  ))
}

#' @title Get post-processing audit paths
#' @description Legacy alias for `get_postpro_output_paths()`.
#' @param config Named configuration list.
#' @return Named list with post-processing output directories.
get_postpro_audit_paths <- function(config) {
  return(get_postpro_output_paths(config))
}

#' @title Initialize post-processing output directory tree
#' @description Creates deterministic output subdirectories under
#' `audit_root_dir`.
#' @param config Named configuration list.
#' @return Named list of post-processing audit paths.
#' @importFrom checkmate assert_list
#'
initialize_postpro_output_root <- function(config) {
  checkmate::assert_list(config, min.len = 1)

  audit_paths <- get_postpro_output_paths(config)
  ensure_directories_exist(
    unlist(audit_paths, use.names = FALSE),
    recurse = TRUE
  )

  return(audit_paths)
}

#' @title Initialize post-processing audit directory tree
#' @description Legacy alias for `initialize_postpro_output_root()`.
#' @param config Named configuration list.
#' @return Named list of post-processing output paths.
initialize_postpro_audit_root <- function(config) {
  return(initialize_postpro_output_root(config))
}

#' @title Generate unified rule template workbook
#' @description Writes a deterministic template workbook with unified rule
#' columns and guidance under the audit template directory. Both `clean` and
#' `harmonize` stages share the same column schema.
#' @param audit_paths Named list from `get_postpro_audit_paths()`.
#' @param overwrite Logical scalar indicating whether existing template is replaced.
#' @return Character scalar written template path.
#' @importFrom checkmate assert_list assert_flag
#' @importFrom writexl write_xlsx
