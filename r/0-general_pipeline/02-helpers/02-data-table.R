# script: data.table helpers
# description: coercion helpers for data.table interoperability.

#' @title ensure data.frame input is a data.table
#' @description lightweight guard that converts a data.frame to a data.table
#' in place using `data.table::setDT()`, avoiding a full memory copy.
#' existing `data.table` inputs are returned immediately with no overhead.
#' callers are responsible for upstream validation; this function performs
#' only the minimal `is.data.table()` class check for speed.
#' @param df data.frame or data.table with zero or more rows.
#' @return data.table object.
#' @importFrom data.table is.data.table setDT
#' @examples
#' ensure_data_table(data.frame(x = 1:3))
ensure_data_table <- function(df) {
  if (!data.table::is.data.table(df)) {
    data.table::setDT(df)
  }
  return(df)
}

#' @title create an independent data.table copy
#' @description returns a deep copy of the input as a data.table. when the
#' input is already a data.table, only `data.table::copy()` is called. when
#' the input is a plain data.frame, `data.table::as.data.table()` already
#' allocates a fresh object, making the additional `copy()` unnecessary.
#' replaces the `copy(as.data.table(x))` double-allocation pattern.
#' callers are responsible for upstream validation.
#' @param df data.frame or data.table with zero or more rows.
#' @return a new data.table that can be modified by reference without affecting
#' the original.
#' @importFrom data.table as.data.table copy is.data.table
#' @examples
#' copy_as_data_table(data.frame(x = 1:3))
copy_as_data_table <- function(df) {
  if (data.table::is.data.table(df)) {
    return(data.table::copy(df))
  }
  return(data.table::as.data.table(df))
}

#' @title coerce to data.table
#' @description validate a data.frame-compatible object and return a
#' `data.table`, preserving `data.table` inputs.
#' @param x data.frame or data.table object.
#' @param min_rows non-negative integer scalar for minimum row requirement.
#' @return data.table.
#' @importFrom checkmate check_data_frame check_int
#' @examples
#' coerce_to_data_table(data.frame(x = 1:2))
coerce_to_data_table <- function(x, min_rows = 0L) {
  assert_or_abort(checkmate::check_int(min_rows, lower = 0))
  assert_or_abort(checkmate::check_data_frame(x, min.rows = min_rows))

  return(ensure_data_table(x))
}
