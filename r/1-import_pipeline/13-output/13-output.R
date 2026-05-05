# output consolidation for import pipeline
validate_output_column_order <- function(config) {
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))

  if (is.null(config$column_order)) {
    cli::cli_abort("`config$column_order` must be defined.")
  }

  assert_or_abort(checkmate::check_character(
    config$column_order,
    any.missing = FALSE,
    min.len = 1,
    unique = TRUE
  ))

  target_schema <- c(
    "hemisphere",
    "continent",
    "country",
    "commodity",
    "variable",
    "unit",
    "year",
    "value",
    "notes",
    "footnotes",
    "yearbook",
    "document"
  )

  assert_or_abort(checkmate::check_subset(
    target_schema,
    choices = config$column_order
  ))

  return(config$column_order)
}

consolidate_audited_dt <- function(dt_list, config) {
  assert_or_abort(checkmate::check_list(dt_list, any.missing = TRUE))

  column_order <- validate_output_column_order(config)

  dt_items <- Filter(Negate(is.null), dt_list)
  dt_items <- lapply(dt_items, coerce_to_data_table)

  if (length(dt_items) == 0) {
    warning_message <- "no data tables were provided for consolidation"
    cli::cli_warn(warning_message)

    return(list(
      data = data.table::data.table(),
      warnings = warning_message
    ))
  }

  dt_combined <- data.table::rbindlist(dt_items, use.names = TRUE, fill = TRUE)

  missing_cols <- setdiff(column_order, colnames(dt_combined))

  if (length(missing_cols) > 0) {
    dt_combined[, (missing_cols) := NA_character_]
  }

  extra_cols <- setdiff(colnames(dt_combined), column_order)
  data.table::setcolorder(dt_combined, c(column_order, extra_cols))

  return(list(data = dt_combined, warnings = character(0)))
}
