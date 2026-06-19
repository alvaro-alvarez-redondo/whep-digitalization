#' @title Write one data table to TSV (high-performance)
#' @description Writes a data.table to a tab-separated `.tsv` file using the
#' C-based `data.table::fwrite` engine.
#' @param data_dt Data table to export.
#' @param output_path Character scalar path to write.
#' @param overwrite Logical scalar overwrite flag.
#' @return Character scalar `output_path`.
#' @importFrom checkmate assert_data_table assert_string assert_flag
#' @importFrom data.table fwrite
write_processed_table_fast <- function(data_dt, output_path, overwrite = TRUE) {
  checkmate::assert_data_table(data_dt)
  checkmate::assert_string(output_path, min.chars = 1)
  checkmate::assert_flag(overwrite)

  if (!overwrite && file.exists(output_path)) {
    cli::cli_abort(
      "file already exists and overwrite is disabled: {.path {output_path}}"
    )
  }

  data.table::fwrite(
    data_dt,
    file = output_path,
    sep = "\t"
  )

  return(output_path)
}
