#' @title Build unique-values cache by layer and column
#' @description Precomputes unique values for every `(layer, column)` pair.
#' @param layer_by_sheet Named list of layer tables by sheet label.
#' @param union_columns Character vector of all columns.
#' @return Named list: first level sheet name, second level column name.
#' @importFrom checkmate assert_list assert_character
build_column_unique_cache <- function(layer_by_sheet, union_columns) {
  checkmate::assert_list(layer_by_sheet, names = "named")
  checkmate::assert_character(union_columns, min.len = 0, any.missing = FALSE)

  cache <- lapply(layer_by_sheet, function(layer_dt) {
    column_values <- lapply(union_columns, function(column_name) {
      compute_unique_column_values(layer_dt, column_name)
    })

    names(column_values) <- union_columns

    return(column_values)
  })

  return(cache)
}

#' @title Write one column-centric lists workbook
#' @description Writes one workbook per column with deterministic sheet logic:
#' all-equal lists produce a single merged sheet (for example
#' `raw_clean_normalize_harmonize`), while partially equal layers are merged
#' using concatenated names (for example `clean_normalize_harmonize`).
#' @param column_name Character scalar column name.
#' @param unique_cache Named cache from `build_column_unique_cache()`.
#' @param config Named configuration list.
#' @param overwrite Logical scalar overwrite flag.
#' @return Character scalar workbook path.
#' @importFrom checkmate assert_string assert_list assert_flag
#' @importFrom writexl write_xlsx
#' @importFrom data.table data.table
write_column_lists_workbook <- function(
  column_name,
  unique_cache,
  config,
  overwrite = TRUE
) {
  checkmate::assert_string(column_name, min.chars = 1)
  checkmate::assert_list(unique_cache, names = "named")
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_flag(overwrite)

  workbook_path <- build_column_lists_export_path(
    config = config,
    column_name = column_name
  )

  raw_values <- unique_cache$raw[[column_name]]
  clean_values <- unique_cache$clean[[column_name]]
  normalize_values <- unique_cache$normalize[[column_name]]
  harmonize_values <- unique_cache$harmonize[[column_name]]

  if (is.null(raw_values)) {
    raw_values <- character(0)
  }
  if (is.null(clean_values)) {
    clean_values <- character(0)
  }
  if (is.null(normalize_values)) {
    normalize_values <- character(0)
  }
  if (is.null(harmonize_values)) {
    harmonize_values <- character(0)
  }

  raw_values_dt <- data.table::data.table(value = raw_values)
  clean_values_dt <- data.table::data.table(value = clean_values)
  normalize_values_dt <- data.table::data.table(value = normalize_values)
  harmonize_values_dt <- data.table::data.table(value = harmonize_values)

  sheet_payloads <- resolve_list_sheet_payloads(
    raw_values_dt = raw_values_dt,
    clean_values_dt = clean_values_dt,
    normalize_values_dt = normalize_values_dt,
    harmonize_values_dt = harmonize_values_dt
  )

  writexl::write_xlsx(sheet_payloads, path = workbook_path, col_names = FALSE)

  return(workbook_path)
}

#' @title Export column-centric lists workbooks
#' @description export one workbook per column. Each workbook contains fixed
#' deterministic layer sheet outputs from `raw`, `clean`, `normalize`, and
#' `harmonize`, with identical layers merged into combined sheet names.
#' Exported columns are controlled by
#' `config$export_config$lists_to_export`; columns not listed there are not
#' exported. When a `future` parallel backend is configured, workbooks are
#' written in parallel.
#' @param config Named configuration list.
#' @param data_objects Optional named list of data.frame/data.table objects.
#' @param overwrite Logical scalar overwrite flag.
#' @param env Environment for automatic object detection when `data_objects` is
#' `NULL`.
#' @return Named character vector of workbook paths keyed by column name.
#' @importFrom checkmate assert_list assert_flag assert_environment
#' @importFrom future.apply future_lapply
#' @importFrom cli cli_abort
export_lists <- function(
  config,
  data_objects = NULL,
  overwrite = TRUE,
  env = .GlobalEnv
) {
  checkmate::assert_list(config, names = "named")
  checkmate::assert_flag(overwrite)
  checkmate::assert_environment(env)

  layer_tables <- collect_layer_tables_for_export(
    data_objects = data_objects,
    env = env
  )

  layer_by_sheet <- build_layer_tables_by_sheet(layer_tables)
  union_columns <- collect_union_columns(layer_by_sheet)

  if (length(union_columns) == 0L) {
    cli::cli_abort(
      "lists export failed: no columns found across detected layers"
    )
  }

  unique_cache <- build_column_unique_cache(
    layer_by_sheet = layer_by_sheet,
    union_columns = union_columns
  )

  export_columns <- resolve_lists_export_columns(
    config = config,
    union_columns = union_columns
  )

  use_parallel <- !inherits(future::plan(), "sequential") &&
    length(export_columns) > 1L

  if (use_parallel) {
    output_paths <- setNames(
      future.apply::future_lapply(
        export_columns,
        function(column_name) {
          write_column_lists_workbook(
            column_name = column_name,
            unique_cache = unique_cache,
            config = config,
            overwrite = overwrite
          )
        },
        future.seed = NULL
      ),
      export_columns
    )
  } else {
    output_paths <- setNames(
      lapply(export_columns, function(column_name) {
        write_column_lists_workbook(
          column_name = column_name,
          unique_cache = unique_cache,
          config = config,
          overwrite = overwrite
        )
      }),
      export_columns
    )
  }

  return(unlist(output_paths, use.names = TRUE))
}
