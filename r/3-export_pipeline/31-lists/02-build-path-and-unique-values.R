#' @title Build lists export path for one column
#' @description Resolves lists directory and returns a deterministic column-based
#' workbook path. Callers must ensure the directory exists before writing
#' (see `run_export_pipeline`).
#' @param config Named configuration list.
#' @param column_name Character scalar column name.
#' @return Character scalar path ending with `_list.xlsx`.
#' @importFrom checkmate assert_list assert_string
#' @importFrom fs path
build_column_lists_export_path <- function(config, column_name) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(column_name, min.chars = 1)

  lists_dir <- get_config_string(
    config = config,
    path = c("paths", "data", "export", "lists"),
    field_name = "config$paths$data$export$lists"
  )

  lists_dir <- here::here(lists_dir)

  return(fs::path(
    lists_dir,
    paste0("unique_", normalize_filename(column_name), ".xlsx")
  ))
}

#' @title Compute sorted unique values for one column
#' @description Returns sorted unique values when column exists; returns empty
#' character vector when the column is absent. When missing values are present,
#' the output prepends a display placeholder label.
#' @param data_dt Data table for one layer.
#' @param column_name Character scalar column name.
#' @param blank_label Character scalar display label for missing values.
#' @return Atomic vector of unique values.
#' @importFrom checkmate assert_data_table assert_string
#' @importFrom cli cli_abort
compute_unique_column_values <- function(
  data_dt,
  column_name,
  blank_label = get_pipeline_constants()$defaults$list_blank_label
) {
  checkmate::assert_data_table(data_dt)
  checkmate::assert_string(column_name, min.chars = 1)
  checkmate::assert_string(blank_label, min.chars = 1)

  if (!column_name %in% names(data_dt)) {
    return(character(0))
  }

  column_values <- data_dt[[column_name]]

  if (is.list(column_values)) {
    cli::cli_abort(
      "column {.val {column_name}} has unsupported list type for list export"
    )
  }

  unique_values <- unique(column_values)
  has_missing_values <- anyNA(unique_values)
  unique_values <- sort(unique_values[!is.na(unique_values)], na.last = TRUE)

  if (has_missing_values) {
    unique_values <- c(blank_label, unique_values)
  }

  return(unique_values)
}

#' @title Build layer tables keyed by sheet names
#' @description Creates deterministic layer table map keyed by
#' `raw/clean/normalize/harmonize`, filling missing layers with empty tables.
#' @param layer_tables Named list of detected layer data tables.
#' @return Named list of data.tables keyed by sheet name.
#' @importFrom checkmate assert_list
#' @importFrom data.table data.table
build_layer_tables_by_sheet <- function(layer_tables) {
  checkmate::assert_list(layer_tables, names = "named")

  layer_order <- get_lists_sheet_order()

  if (length(layer_tables) == 0) {
    layer_by_sheet <- lapply(layer_order, function(sheet_name) {
      data.table::data.table()
    })
    names(layer_by_sheet) <- layer_order

    return(layer_by_sheet)
  }

  detected_sheet_names <- vapply(
    names(layer_tables),
    infer_layer_sheet_name,
    character(1)
  )

  first_object_by_sheet <- tapply(
    names(layer_tables),
    detected_sheet_names,
    function(object_names) object_names[[1]],
    simplify = TRUE
  )

  layer_by_sheet <- lapply(layer_order, function(sheet_name) {
    selected_object <- first_object_by_sheet[[sheet_name]]

    if (is.null(selected_object) || is.na(selected_object)) {
      return(data.table::data.table())
    }

    return(data.table::as.data.table(layer_tables[[selected_object]]))
  })

  names(layer_by_sheet) <- layer_order

  return(layer_by_sheet)
}

#' @title Collect union of columns across all layer tables
#' @description Computes deterministic sorted union of column names from all
#' available layers.
#' @param layer_by_sheet Named list of data.tables keyed by sheet label.
#' @return Character vector of column names.
#' @importFrom checkmate assert_list
collect_union_columns <- function(layer_by_sheet) {
  checkmate::assert_list(layer_by_sheet, names = "named")

  union_columns <- unlist(
    lapply(layer_by_sheet, names),
    use.names = FALSE
  ) |> 
    unique() |> 
    sort()

  return(union_columns)
}
