#' @title Resolve configured columns for list export
#' @description Returns deterministic list-export columns by honoring
#' `config$export_config$lists_to_export` and retaining only columns present
#' across detected layers.
#' @param config Named configuration list.
#' @param union_columns Character vector of detected columns across layers.
#' @return Character vector of columns to export in configured order.
#' @importFrom checkmate assert_list assert_character
#' @importFrom purrr pluck
#' @importFrom cli cli_abort
resolve_lists_export_columns <- function(config, union_columns) {
  checkmate::assert_list(config, names = "named")
  checkmate::assert_character(union_columns, min.len = 0, any.missing = FALSE)

  configured_columns <- purrr::pluck(
    config,
    "export_config",
    "lists_to_export",
    .default = NULL
  )

  if (is.null(configured_columns)) {
    cli::cli_abort(
      "`config$export_config$lists_to_export` must be defined for list export"
    )
  }

  checkmate::assert_character(
    configured_columns,
    min.len = 1,
    any.missing = FALSE,
    unique = TRUE
  )

  export_columns <- configured_columns[configured_columns %in% union_columns]

  if (length(export_columns) == 0L) {
    cli::cli_abort(c(
      "lists export failed: none of the configured columns are present in detected layers.",
      "i" = "configured columns: {.val {configured_columns}}",
      "i" = "detected columns: {.val {union_columns}}"
    ))
  }

  return(export_columns)
}

#' @title Normalize table for strict deterministic comparison
#' @description Drops `year` column when present, aligns column names and
#' order, and sorts rows so strict `identical()` can be applied deterministically.
#' @param data_dt Data table for normalization.
#' @return normalize data.table.
#' @importFrom checkmate assert_data_table
normalize_for_comparison <- function(data_dt) {
  checkmate::assert_data_table(data_dt)

  normalize_dt <- data.table::copy(data_dt)

  if ("year" %in% names(normalize_dt)) {
    normalize_dt[, year := NULL]
  }

  normalize_columns <- sort(names(normalize_dt))

  if (length(normalize_columns) == 0L) {
    return(normalize_dt)
  }

  data.table::setcolorder(normalize_dt, normalize_columns)
  data.table::setorderv(normalize_dt, normalize_columns, na.last = TRUE)

  return(normalize_dt)
}

#' @title Compare two list tables deterministically
#' @description Returns `TRUE` when two tables are strictly equal after
#' deterministic normalization.
#' @param left_dt Data table for left side.
#' @param right_dt Data table for right side.
#' @return Logical scalar.
#' @importFrom checkmate assert_data_table
are_list_tables_identical <- function(
  left_dt,
  right_dt
) {
  checkmate::assert_data_table(left_dt)
  checkmate::assert_data_table(right_dt)

  normalize_left <- normalize_for_comparison(left_dt)
  normalize_right <- normalize_for_comparison(right_dt)

  return(identical(normalize_left, normalize_right))
}

#' @title Resolve deterministic sheet payloads for one column
#' @description Applies deterministic equality grouping across raw, clean,
#' normalize, and harmonize unique-value tables and returns the sheets that
#' must be written.
#' @param raw_values_dt Data table of raw values.
#' @param clean_values_dt Data table of clean values.
#' @param normalize_values_dt Data table of normalize values.
#' @param harmonize_values_dt Data table of harmonize values.
#' @return Named list of sheet payload data.tables.
#' @importFrom checkmate assert_data_table
resolve_list_sheet_payloads <- function(
  raw_values_dt,
  clean_values_dt,
  normalize_values_dt,
  harmonize_values_dt
) {
  checkmate::assert_data_table(raw_values_dt)
  checkmate::assert_data_table(clean_values_dt)
  checkmate::assert_data_table(normalize_values_dt)
  checkmate::assert_data_table(harmonize_values_dt)

  layer_values <- list(
    raw = raw_values_dt,
    clean = clean_values_dt,
    normalize = normalize_values_dt,
    harmonize = harmonize_values_dt
  )

  grouped_layers <- list()

  for (layer_name in get_lists_sheet_order()) {
    current_dt <- layer_values[[layer_name]]
    matched_group_index <- NA_integer_

    if (length(grouped_layers) > 0L) {
      for (group_index in seq_along(grouped_layers)) {
        representative_dt <- layer_values[[grouped_layers[[group_index]][[1]]]]

        if (are_list_tables_identical(current_dt, representative_dt)) {
          matched_group_index <- group_index
          break
        }
      }
    }

    if (is.na(matched_group_index)) {
      grouped_layers[[length(grouped_layers) + 1L]] <- layer_name
    } else {
      grouped_layers[[matched_group_index]] <- c(
        grouped_layers[[matched_group_index]],
        layer_name
      )
    }
  }

  sheet_payloads <- list()

  for (group_layers in grouped_layers) {
    sheet_name <- paste(group_layers, collapse = "_")
    sheet_payloads[[sheet_name]] <- layer_values[[group_layers[[1]]]]
  }

  return(sheet_payloads)
}
