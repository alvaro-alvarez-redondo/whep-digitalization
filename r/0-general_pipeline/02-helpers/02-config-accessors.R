# script: config accessors
# description: helpers for extracting config fields and export paths.

#' @title extract and validate string field from nested config list
#' @description retrieves a nested field from `config` using `purrr::pluck()`,
#' aborts with a cli error when the field is missing, and validates that the
#' retrieved value is a non-empty character scalar.
#' @param config named list containing pipeline settings.
#' @param path character vector that defines the nested access path.
#' @param field_name character scalar used in validation error messages.
#' @return non-empty character scalar extracted from the config list.
#' @importFrom purrr pluck
#' @importFrom checkmate check_list check_character check_string
#' @importFrom cli cli_abort
#' @examples
#' config <- list(paths = list(data = list(export = list(processed = "tmp"))))
#' get_config_string(config, c("paths", "data", "export", "processed"), "field")
get_config_string <- function(config, path, field_name) {
  assert_or_abort(checkmate::check_list(config, min.len = 1))
  assert_or_abort(checkmate::check_character(
    path,
    min.len = 1,
    any.missing = FALSE
  ))
  assert_or_abort(checkmate::check_string(field_name, min.chars = 1))

  field_value <- purrr::pluck(config, !!!path, .default = NULL)

  if (is.null(field_value)) {
    cli::cli_abort("`{field_name}` must be defined.")
  }

  assert_or_abort(checkmate::check_string(field_value, min.chars = 1))

  return(field_value)
}

#' @title build normalize export path from pipeline config
#' @description constructs an output path for `processed` or `lists` export
#' using folder and suffix metadata from the pipeline config. callers must
#' ensure the output directory exists before writing (see `run_export_pipeline`).
#' @param config named list with non-empty structure. validated with
#' `checkmate::check_list(min.len = 1)`. must contain
#' `paths$data$export$processed`, `paths$data$export$lists`,
#' `export_config$data_suffix`, and `export_config$list_suffix` as non-empty
#' character scalars.
#' @param base_name non-empty character scalar used as output basename before
#' normalization and suffix append. validated with
#' `checkmate::check_string(min.chars = 1)`.
#' @param type character scalar. one of `"processed"` or `"lists"`.
#' @param use_here logical scalar. when `true`, resolve export directories
#' with `here::here()` to guarantee project-root-relative output paths.
#' @return character scalar path generated with `fs::path()`.
#' @importFrom checkmate check_flag check_list check_string
#' @importFrom fs path
#' @importFrom here here
#' @examples
#' config <- list(
#'   paths = list(data = list(export = list(processed = "tmp", lists = "tmp"))),
#'   export_config = list(data_suffix = "_data.xlsx", list_suffix = "_list.xlsx")
#' )
#' generate_export_path(config, "food balance", "processed")
generate_export_path <- function(
  config,
  base_name,
  type = c("processed", "lists"),
  use_here = TRUE
) {
  assert_or_abort(checkmate::check_list(config, min.len = 1))
  assert_or_abort(checkmate::check_string(base_name, min.chars = 1))
  assert_or_abort(checkmate::check_flag(use_here))

  type <- match.arg(type)

  folder <- switch(
    type,
    processed = get_config_string(
      config = config,
      path = c("paths", "data", "export", "processed"),
      field_name = "config$paths$data$export$processed"
    ),
    lists = get_config_string(
      config = config,
      path = c("paths", "data", "export", "lists"),
      field_name = "config$paths$data$export$lists"
    )
  )

  suffix <- switch(
    type,
    processed = get_config_string(
      config = config,
      path = c("export_config", "data_suffix"),
      field_name = "config$export_config$data_suffix"
    ),
    lists = get_config_string(
      config = config,
      path = c("export_config", "list_suffix"),
      field_name = "config$export_config$list_suffix"
    )
  )

  output_folder <- if (use_here) {
    here::here(folder)
  } else {
    folder
  }

  return(fs::path(output_folder, paste0(normalize_filename(base_name), suffix)))
}
