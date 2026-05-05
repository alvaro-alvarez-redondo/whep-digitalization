# script: io caching
# description: cached IO helpers for pipeline data.

#' @title Cached unzip with timestamp guard
#' @description Extracts a `.zip` archive only when the source archive is newer
#' than the target directory or when the target does not exist. This avoids
#' redundant `utils::unzip()` calls that dominate I/O profiling traces.
#' @param zip_path Character scalar path to the `.zip` file.
#' @param exdir Character scalar path to the extraction target directory.
#' @param overwrite Logical scalar; when `TRUE`, always extract regardless of
#' timestamps.
#' @return Invisible character scalar `exdir`.
#' @importFrom checkmate assert_string assert_flag assert_file_exists
#' @importFrom fs dir_exists dir_create file_info
#' @importFrom utils unzip
#' @importFrom cli cli_alert_info
#' @examples
#' # cached_unzip("data/archive.zip", "data/extracted")
cached_unzip <- function(zip_path, exdir, overwrite = FALSE) {
  checkmate::assert_string(zip_path, min.chars = 1)
  checkmate::assert_string(exdir, min.chars = 1)
  checkmate::assert_flag(overwrite)
  checkmate::assert_file_exists(zip_path, access = "r")

  needs_extract <- overwrite || !fs::dir_exists(exdir)

  if (!needs_extract) {
    zip_info <- fs::file_info(zip_path)
    exdir_info <- fs::file_info(exdir)
    needs_extract <- is.na(exdir_info$modification_time) ||
      zip_info$modification_time > exdir_info$modification_time
  }

  if (needs_extract) {
    fs::dir_create(exdir, recurse = TRUE)
    utils::unzip(zip_path, exdir = exdir, overwrite = TRUE)
    cli::cli_alert_info("Extracted {.file {zip_path}} to {.path {exdir}}")
  }

  return(invisible(exdir))
}
