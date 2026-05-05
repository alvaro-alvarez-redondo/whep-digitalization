# script: data cleaning
# description: shared data filtering helpers.

#' @title Drop rows where value column is NA
#' @description Removes rows from a `data.table` where the specified value
#' column is `NA`. Controlled by the `whep.drop_na_values` option (default
#' `TRUE`). When the option is `FALSE`, the data is returned unchanged.
#' @param dt `data.table` to filter.
#' @param value_column Character scalar column name to check for `NA` values.
#' @return Filtered `data.table` (copy when rows are dropped; original when
#' nothing changes or the toggle is off).
#' @importFrom checkmate assert_string
drop_na_value_rows <- function(
  dt,
  value_column = get_pipeline_constants()$defaults$value_column
) {
  if (!(data.table::is.data.table(dt) || is.data.frame(dt))) {
    cli::cli_abort("{.arg dt} must be a data.frame or data.table")
  }
  checkmate::assert_string(value_column, min.chars = 1)

  drop_na_option <- get_pipeline_constants()$toggle_options$drop_na_values
  if (!isTRUE(getOption(drop_na_option, TRUE))) {
    return(dt)
  }

  if (!value_column %in% names(dt)) {
    return(dt)
  }

  value_vec <- dt[[value_column]]

  if (data.table::is.data.table(dt)) {
    if (!anyNA(value_vec)) {
      return(dt)
    }

    return(dt[!is.na(value_vec)])
  }

  if (!anyNA(value_vec)) {
    return(dt)
  }

  return(dt[!is.na(value_vec), , drop = FALSE])
}
