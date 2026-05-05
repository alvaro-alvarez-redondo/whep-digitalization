# discovery helpers for import pipeline
discover_files <- function(import_folder) {
  assert_or_abort(checkmate::check_string(import_folder, min.chars = 1))
  assert_or_abort(checkmate::check_directory_exists(import_folder))

  files_found <- fs::dir_ls(
    path = import_folder,
    recurse = TRUE,
    type = "file",
    glob = "*.xlsx"
  )

  if (length(files_found) == 0) {
    cli::cli_warn(c(
      "no xlsx files were found in the import folder",
      "i" = "folder: {import_folder}"
    ))

    return(build_empty_file_metadata())
  }

  metadata <- extract_file_metadata(files_found)

  return(metadata)
}

discover_pipeline_files <- function(config) {
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))

  import_folder <- config[["paths"]][["data"]][["import"]][["raw"]]

  if (is.null(import_folder)) {
    cli::cli_abort("`config$paths$data$import$raw` must be defined.")
  }

  assert_or_abort(checkmate::check_string(import_folder, min.chars = 1))
  assert_or_abort(checkmate::check_directory_exists(import_folder))

  metadata <- discover_files(import_folder)

  return(metadata)
}
