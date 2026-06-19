#' Get post-processing output directory paths
#' Resolves audit, diagnostics, templates, and runtime-cache directories from
#' `config`.
#' @param config Named configuration list.
#' @return Named list of directory paths.
#' @examples
#' \dontrun{
#' get_postpro_output_paths(config)
#' }
get_postpro_output_paths <- function(config) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(
    config$paths$data$audit$audit_root_dir,
    min.chars = 1
  )

  audit_root_dir <- config$paths$data$audit$audit_root_dir
  constants <- get_pipeline_constants()

  return(list(
    audit_root_dir = audit_root_dir,
    audit_dir = config$paths$data$audit$audit_dir %||%
      file.path(audit_root_dir, constants$postpro$audit_dir_name),
    diagnostics_dir = config$paths$data$audit$diagnostics_dir %||%
      file.path(audit_root_dir, constants$postpro$diagnostics_dir_name),
    templates_dir = config$paths$data$audit$templates_dir %||%
      file.path(audit_root_dir, constants$postpro$templates_dir_name),
    runtime_cache_dir = config$paths$data$audit$runtime_cache_dir %||%
      file.path(audit_root_dir, constants$postpro$runtime_cache_dir_name)
  ))
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
