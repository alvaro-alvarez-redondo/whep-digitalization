# script: deterministic sorting
# description: sorting helpers for pipeline stage outputs.

#' @title Sort pipeline stage data deterministically
#' @description Applies deterministic row sorting for pipeline stage outputs
#' using the canonical business key order:
#' `hemisphere`, `continent`, `country`, `commodity`, `variable`, `unit`,
#' `year`, `value`, `notes`, `footnotes`, `yearbook`, and `document`.
#' Missing sort columns are ignored, and sorting is skipped when none are
#' present.
#' @param dt Data frame or `data.table` to sort.
#' @param sort_columns Character vector sort priority.
#' @return `data.table` sorted in place when possible.
#' @importFrom checkmate check_character
#' @examples
#' sort_pipeline_stage_dt(data.table::data.table(country = "x", year = "2020"))
sort_pipeline_stage_dt <- function(
  dt,
  sort_columns = get_pipeline_constants()$sorting$stage_row_order
) {
  sorted_dt <- coerce_to_data_table(dt)
  assert_or_abort(checkmate::check_character(
    sort_columns,
    any.missing = FALSE,
    min.len = 1
  ))

  present_sort_columns <- intersect(sort_columns, names(sorted_dt))

  if (length(present_sort_columns) == 0L || nrow(sorted_dt) <= 1L) {
    return(sorted_dt)
  }

  data.table::setorderv(sorted_dt, present_sort_columns, na.last = TRUE)

  return(sorted_dt)
}
