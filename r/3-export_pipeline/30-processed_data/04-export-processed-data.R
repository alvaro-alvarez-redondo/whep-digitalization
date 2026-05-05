#' @title Export processed layer tables
#' @description Detects all layer tables for traceability, then export only the
#' layers listed in `config$export_config$export_layers` (default:
#' `"harmonize"`) into `data/3-export/processed_data` using the
#' high-performance writer. Callers must ensure the processed-data export
#' directory exists before calling this function (see `run_export_pipeline`).
#' @param config Named configuration list.
#' @param data_objects Optional named list of data.frame/data.table objects.
#' @param overwrite Logical scalar overwrite flag.
#' @param env Environment for automatic object detection when `data_objects` is
#' `NULL`.
#' @return Named character vector of processed export paths.
#' @importFrom checkmate assert_list assert_flag assert_environment assert_character
#' @importFrom purrr imap_chr
export_processed_data <- function(
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

  export_layers <- config$export_config$export_layers
  if (is.null(export_layers)) {
    export_layers <- c("harmonize")
  }
  checkmate::assert_character(export_layers, min.len = 1, any.missing = FALSE)

  export_pattern <- paste0("_(", paste(export_layers, collapse = "|"), ")$")
  export_tables <- layer_tables[grepl(export_pattern, names(layer_tables))]

  if (length(export_tables) == 0L) {
    cli::cli_abort(c(
      "no exportable layer tables found.",
      "i" = "detected layers: {.val {names(layer_tables)}}",
      "x" = "config$export_config$export_layers is set to: {.val {export_layers}}"
    ))
  }

  processed_paths <- purrr::imap_chr(
    export_tables,
    function(data_dt, object_name) {
      output_path <- build_processed_export_path(
        config = config,
        object_name = object_name
      )

      write_processed_table_fast(
        data_dt = data_dt,
        output_path = output_path,
        overwrite = overwrite
      )
    }
  )

  return(processed_paths)
}
