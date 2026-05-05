# script: directory management
# description: utilities for creating and validating pipeline directories.

#' @title resolve audit root directory
#' @description safely extracts the optional audit root directory from a
#' pipeline-like `paths` list without assuming nested members are present.
#' @param paths named or unnamed list that may contain
#' `paths$data$audit$audit_root_dir`.
#' @return character scalar audit root directory when configured; otherwise
#' `NULL`.
#' @importFrom checkmate assert_list assert_string
#' @importFrom purrr pluck
#' @examples
#' resolve_audit_root_dir(list())
resolve_audit_root_dir <- function(paths) {
  checkmate::assert_list(paths)

  audit_root_dir <- purrr::pluck(
    paths,
    "data",
    "audit",
    "audit_root_dir",
    .default = NULL
  )

  if (!is.null(audit_root_dir)) {
    checkmate::assert_string(audit_root_dir, min.chars = 1)
  }

  return(audit_root_dir)
}


#' @title ensure directories exist
#' @description creates directories in deterministic sorted order.
#' @param directories character vector of directory paths.
#' @param recurse logical scalar passed to `fs::dir_create()`.
#' @return invisible character vector of created directory paths.
#' @importFrom checkmate assert_character assert_flag
#' @importFrom fs dir_create
#' @examples
#' ensure_directories_exist(file.path(tempdir(), c("a", "b")))
ensure_directories_exist <- function(directories, recurse = TRUE) {
  checkmate::assert_character(directories, any.missing = FALSE)
  checkmate::assert_flag(recurse)

  if (length(directories) == 0) {
    return(invisible(character(0)))
  }

  normalize_directories <- directories |>
    unique() |>
    sort()

  fs::dir_create(normalize_directories, recurse = recurse)

  return(invisible(normalize_directories))
}

#' @title delete directory if it exists
#' @description deletes a directory path when it exists and optionally tolerates
#' permission errors while keeping deterministic error handling.
#' @param directory character scalar directory path.
#' @param tolerate_permission_errors logical scalar; when `TRUE`, permission
#' and lock-related deletion errors return `FALSE` instead of aborting.
#' @return invisible logical scalar indicating whether a directory was deleted.
#' @importFrom checkmate assert_string assert_flag
#' @importFrom cli cli_abort
#' @importFrom fs dir_exists dir_delete
#' @importFrom purrr safely
#' @examples
#' delete_directory_if_exists(file.path(tempdir(), "nonexistent"))
delete_directory_if_exists <- function(
  directory,
  tolerate_permission_errors = FALSE
) {
  checkmate::assert_string(directory, min.chars = 1)
  checkmate::assert_flag(tolerate_permission_errors)

  if (!fs::dir_exists(directory)) {
    return(invisible(FALSE))
  }

  constants <- get_pipeline_constants()
  permission_error_pattern <- constants$patterns$permission_error

  delete_result <- purrr::safely(fs::dir_delete)(directory)

  if (!is.null(delete_result$error)) {
    error_message <- as.character(delete_result$error$message)
    permission_error <- grepl(
      permission_error_pattern,
      error_message,
      ignore.case = TRUE
    )

    if (tolerate_permission_errors && permission_error) {
      return(invisible(FALSE))
    }

    cli::cli_abort(
      "failed to delete existing folder {.path {directory}}: {error_message}"
    )
  }

  return(invisible(TRUE))
}

#' @title create required directories
#' @description validates a nested list of paths, flattens it to a character
#' vector, normalizes file paths to their parent directories, excludes audit
#' directories for lazy creation, creates every remaining directory if missing,
#' and returns the resolved directory vector invisibly.
#' @param paths named or unnamed list containing character path elements. must
#' be a non-empty list that resolves to a non-empty character vector with no
#' missing values.
#' @return invisible character vector of directories passed to
#' `fs::dir_create()`.
#' @importFrom checkmate assert_list assert_character
#' @importFrom fs dir_create path_file path_dir path_norm
#' @importFrom purrr map_chr
#' @examples
#' temp_paths <- list(a = file.path(tempdir(), "a"), b = file.path(tempdir(), "b"))
#' create_required_directories(temp_paths)
create_required_directories <- function(paths) {
  checkmate::assert_list(paths, min.len = 1)

  constants <- get_pipeline_constants()
  file_extension_pattern <- constants$patterns$file_extension

  all_paths <- paths |>
    unlist(recursive = TRUE, use.names = FALSE)

  checkmate::assert_character(all_paths, any.missing = FALSE, min.len = 1)

  all_directories <- all_paths |>
    vapply(
      \(path_value) {
        path_file_name <- fs::path_file(path_value)

        if (grepl(file_extension_pattern, path_file_name)) {
          return(fs::path_dir(path_value))
        }

        path_value
      },
      character(1)
    ) |>
    unique() |>
    sort()

  audit_root_dir <- resolve_audit_root_dir(paths)

  if (is.character(audit_root_dir) && length(audit_root_dir) == 1) {
    normalize_audit_root <- fs::path_norm(audit_root_dir)
    all_directories <- all_directories[
      !vapply(
        all_directories,
        \(path_value) {
          normalize_path <- fs::path_norm(path_value)
          identical(normalize_path, normalize_audit_root)
        },
        logical(1)
      )
    ]
  }

  if (length(all_directories) > 0) {
    ensure_directories_exist(all_directories, recurse = TRUE)
  }

  return(invisible(all_directories))
}

#' @title ensure output directories
#' @description creates parent directories for generated output files only when
#' at least one file path is provided.
#' @param output_paths character vector of file paths that will be generated.
#' @return invisible character vector of parent directories that were created.
#' @importFrom checkmate assert_character
#' @importFrom fs dir_create path_dir
#' @examples
#' output_paths <- file.path(tempdir(), "audit", "dataset", "result.xlsx")
#' ensure_output_directories(output_paths)
ensure_output_directories <- function(output_paths) {
  checkmate::assert_character(output_paths, any.missing = FALSE)

  if (length(output_paths) == 0) {
    return(invisible(character(0)))
  }

  output_directories <- unique(fs::path_dir(output_paths))
  ensure_directories_exist(output_directories, recurse = TRUE)

  return(invisible(output_directories))
}
