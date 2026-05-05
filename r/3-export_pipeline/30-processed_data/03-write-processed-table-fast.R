#' @title Write one data table to Excel (high-performance)
#' @description Writes a data.table to a single-sheet `.xlsx` file using the
#' C-based `writexl` engine.
#' @param data_dt Data table to export.
#' @param output_path Character scalar path to write.
#' @param overwrite Logical scalar overwrite flag.
#' @return Character scalar `output_path`.
#' @importFrom checkmate assert_data_table assert_string assert_flag
#' @importFrom writexl write_xlsx
write_processed_table_fast <- function(data_dt, output_path, overwrite = TRUE) {
  checkmate::assert_data_table(data_dt)
  checkmate::assert_string(output_path, min.chars = 1)
  checkmate::assert_flag(overwrite)

  if (!overwrite && file.exists(output_path)) {
    cli::cli_abort(
      "file already exists and overwrite is disabled: {.path {output_path}}"
    )
  }

  writexl::write_xlsx(
    list(processed_data = data_dt),
    path = output_path
  )

  return(output_path)
}
