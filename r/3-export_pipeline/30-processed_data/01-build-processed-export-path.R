#' @title Build processed-data export path for an object
#' @description Resolves the processed export directory from config and returns
#' an object-name-based workbook path. Callers must ensure the directory exists
#' before writing (see `export_processed_data`).
#' @param config Named configuration list with
#' `paths$data$export$processed`.
#' @param object_name Character scalar object name.
#' @return Character scalar path ending with `.xlsx`.
#' @importFrom checkmate assert_list assert_string
#' @importFrom fs path
build_processed_export_path <- function(config, object_name) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(object_name, min.chars = 1)

  processed_dir <- get_config_string(
    config = config,
    path = c("paths", "data", "export", "processed"),
    field_name = "config$paths$data$export$processed"
  )

  processed_dir <- here::here(processed_dir)

  return(fs::path(
    processed_dir,
    paste0(normalize_filename(object_name), ".xlsx")
  ))
}
