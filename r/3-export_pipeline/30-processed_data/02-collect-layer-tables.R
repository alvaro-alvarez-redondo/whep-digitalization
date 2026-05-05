#' @title Detect available layer tables for export
#' @description Discovers available data.frame/data.table objects that end with
#' configured layer suffixes.
#' @param data_objects Optional named list of data objects.
#' @param env Environment used for automatic detection when `data_objects` is
#' `NULL`.
#' @param layer_suffixes Character vector of supported layer suffixes.
#' @return Named list of data.table objects keyed by original object names.
#' @importFrom checkmate assert_environment assert_character assert_list
#' @importFrom cli cli_abort
#' @importFrom data.table as.data.table
#' @importFrom purrr keep map
collect_layer_tables_for_export <- function(
  data_objects = NULL,
  env = .GlobalEnv,
  layer_suffixes = c("raw", "clean", "normalize", "harmonize")
) {
  checkmate::assert_environment(env)
  checkmate::assert_character(
    layer_suffixes,
    min.len = 1,
    any.missing = FALSE,
    unique = TRUE
  )

  layer_pattern <- paste0("_(", paste(layer_suffixes, collapse = "|"), ")$")

  is_valid_layer_name <- function(object_name) {
    return(
      !is.na(object_name) &&
        nzchar(object_name) &&
        grepl(layer_pattern, object_name) &&
        !grepl("_post_processed$", object_name) &&
        !grepl("_wide_raw$", object_name)
    )
  }

  if (is.null(data_objects)) {
    candidate_names <- ls(envir = env, all.names = TRUE)
    valid_candidate_names <- Filter(is_valid_layer_name, candidate_names)

    detected_tables <- purrr::keep(
      setNames(
        lapply(valid_candidate_names, get, envir = env, inherits = TRUE),
        valid_candidate_names
      ),
      is.data.frame
    )
  } else {
    checkmate::assert_list(data_objects, names = "named", any.missing = TRUE)

    object_names <- names(data_objects)
    valid_name_mask <- vapply(object_names, is_valid_layer_name, logical(1))

    detected_tables <- data_objects[valid_name_mask]
    detected_tables <- purrr::keep(detected_tables, is.data.frame)
  }

  if (length(detected_tables) == 0L) {
    cli::cli_abort(c(
      "no layer tables detected for export.",
      "x" = "expected object names ending in: {.val {layer_suffixes}}",
      "i" = "excluded suffixes include {.val _post_processed} and {.val _wide_raw}"
    ))
  }

  detected_tables <- detected_tables[sort(names(detected_tables))]

  detected_tables <- detected_tables[
    !grepl("_post_processed$", names(detected_tables))
  ]

  ordered_names <- sort(names(detected_tables))
  detected_tables <- detected_tables[ordered_names]

  return(purrr::map(detected_tables, data.table::as.data.table))
}
