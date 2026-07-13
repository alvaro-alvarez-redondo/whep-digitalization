# script: standardize units — row aggregation
# description: post-standardization duplicate-group aggregation
# (compute_duplicate_group_row_mask, aggregate_duplicate_groups,
# aggregate_standardized_rows, extract_aggregated_rows) and diagnostics
# attachment. Split from 24-standardize-engine.R (>500-line policy); pure
# definitions sourced with the rest of the 24-standardize_units stage.

#' @title Compute duplicate-group row mask
#' @description Returns logical mask selecting rows that belong to duplicate
#' groups defined by `group_cols`.
#' @param dt `data.table` to inspect.
#' @param group_cols Character vector of grouping columns.
#' @return Logical vector with one element per row in `dt`.
#' @importFrom checkmate assert_data_table assert_character
compute_duplicate_group_row_mask <- function(dt, group_cols) {
  checkmate::assert_data_table(dt)
  checkmate::assert_character(group_cols, any.missing = FALSE)

  if (nrow(dt) == 0L || length(group_cols) == 0L) {
    return(rep(FALSE, nrow(dt)))
  }

  duplicate_forward <- duplicated(dt, by = group_cols)

  if (!any(duplicate_forward)) {
    return(rep(FALSE, nrow(dt)))
  }

  duplicate_backward <- duplicated(dt, by = group_cols, fromLast = TRUE)

  return(duplicate_forward | duplicate_backward)
}

#' @title Aggregate duplicate groups
#' @description Aggregates duplicate-group rows by summing `value_column` with
#' deterministic all-NA semantics.
#' @param dt `data.table` with rows to aggregate.
#' @param group_cols Character vector of grouping columns.
#' @param value_column Character scalar value column name.
#' @return Aggregated `data.table`.
#' @importFrom checkmate assert_data_table assert_character assert_string
aggregate_duplicate_groups <- function(dt, group_cols, value_column) {
  checkmate::assert_data_table(dt)
  checkmate::assert_character(group_cols, any.missing = FALSE)
  checkmate::assert_string(value_column, min.chars = 1)

  if (nrow(dt) == 0L) {
    return(dt[0L, ])
  }

  value_vector <- dt[[value_column]]

  if (!anyNA(value_vector)) {
    if (identical(value_column, "value")) {
      return(dt[, .(value = sum(value)), by = group_cols])
    }

    aggregated_dt <- dt[,
      .(agg_value_tmp_ = sum(get(value_column))),
      by = group_cols
    ]
    data.table::setnames(aggregated_dt, "agg_value_tmp_", value_column)

    return(aggregated_dt)
  }

  if (identical(value_column, "value")) {
    aggregated_dt <- dt[,
      .(
        agg_value_tmp_ = sum(value, na.rm = TRUE),
        non_na_count_tmp_ = sum(!is.na(value))
      ),
      by = group_cols
    ]
  } else {
    aggregated_dt <- dt[,
      {
        values <- get(value_column)

        .(
          agg_value_tmp_ = sum(values, na.rm = TRUE),
          non_na_count_tmp_ = sum(!is.na(values))
        )
      },
      by = group_cols
    ]
  }

  aggregated_dt[non_na_count_tmp_ == 0L, agg_value_tmp_ := NA_real_]
  aggregated_dt[, non_na_count_tmp_ := NULL]
  data.table::setnames(aggregated_dt, "agg_value_tmp_", value_column)

  return(aggregated_dt)
}

#' @title Aggregate standardized rows
#' @description Collapses rows where all columns except a numeric measure
#' (`value_column`) are identical by summing the measure. Preserves column
#' order and schema. Returns `NA` for groups where every value is `NA`;
#' otherwise sums non-`NA` values. Idempotent: re-running on an
#' already-unique table is a no-op.
#' @param dt `data.table` to aggregate.
#' @param value_column Character scalar name of the numeric column to sum.
#' @return Aggregated `data.table` with the same column order and schema.
#' @importFrom checkmate assert_data_table assert_string
#' @importFrom data.table setcolorder setnames anyDuplicated
aggregate_standardized_rows <- function(dt, value_column = "value") {
  checkmate::assert_data_table(dt)
  checkmate::assert_string(value_column, min.chars = 1)

  if (!value_column %in% names(dt)) {
    cli::cli_abort("value column {.val {value_column}} not found in data")
  }

  if (nrow(dt) <= 1L) {
    return(dt)
  }

  group_cols <- setdiff(names(dt), value_column)

  if (length(group_cols) == 0L) {
    vals <- dt[[value_column]]
    agg_val <- if (all(is.na(vals))) NA_real_ else sum(vals, na.rm = TRUE)
    result <- data.table::data.table(agg_value_tmp_ = agg_val)
    data.table::setnames(result, "agg_value_tmp_", value_column)
    return(result)
  }

  duplicate_group_mask <- compute_duplicate_group_row_mask(
    dt = dt,
    group_cols = group_cols
  )

  if (!any(duplicate_group_mask)) {
    return(dt)
  }

  original_order <- names(dt)
  if (all(duplicate_group_mask)) {
    result <- aggregate_duplicate_groups(
      dt = dt,
      group_cols = group_cols,
      value_column = value_column
    )

    data.table::setcolorder(result, original_order)

    return(result)
  }

  unique_rows <- dt[!duplicate_group_mask]
  duplicate_rows <- dt[duplicate_group_mask]

  aggregated_duplicate_rows <- aggregate_duplicate_groups(
    dt = duplicate_rows,
    group_cols = group_cols,
    value_column = value_column
  )

  result <- data.table::rbindlist(
    list(unique_rows, aggregated_duplicate_rows),
    use.names = TRUE,
    fill = TRUE
  )

  data.table::setcolorder(result, original_order)

  return(result)
}

#' @title Extract rows that will be aggregated
#' @description Returns only the rows from a pre-aggregation data.table that
#' belong to duplicate groups — i.e. the rows that `aggregate_standardized_rows()`
#' will collapse by summing. Groups are defined by all columns except
#' `value_column`. If there are no duplicates, returns an empty data.table with
#' the same schema.
#' @param dt `data.table` before aggregation.
#' @param value_column Character scalar name of the numeric column to sum.
#' @return `data.table` containing only rows from duplicate groups, with the
#'   same column order and schema as `dt`.
#' @importFrom checkmate assert_data_table assert_string
#' @importFrom data.table anyDuplicated
extract_aggregated_rows <- function(dt, value_column = "value") {
  checkmate::assert_data_table(dt)
  checkmate::assert_string(value_column, min.chars = 1)

  if (!value_column %in% names(dt)) {
    cli::cli_abort("value column {.val {value_column}} not found in data")
  }

  if (nrow(dt) == 0L) {
    return(dt)
  }

  group_cols <- setdiff(names(dt), value_column)

  if (length(group_cols) == 0L) {
    return(dt[0L, ])
  }

  duplicate_group_mask <- compute_duplicate_group_row_mask(
    dt = dt,
    group_cols = group_cols
  )

  if (!any(duplicate_group_mask)) {
    return(dt[0L, ])
  }

  return(dt[duplicate_group_mask])
}

#' @title Attach standardize layer diagnostics
#' @description Creates and attaches standardized diagnostics payload to the
#' standardized dataset.
#' @param standardized_dt standardized data.table.
#' @param clean_rows_count Integer number of input rows.
#' @param matched_count Integer matched row count.
#' @param unmatched_count Integer unmatched row count.
#' @param rules_count Integer number of loaded rules.
#' @param rule_sources Character vector of source rule files.
#' @param aggregation_enabled Logical scalar whether aggregation was applied.
#' @param rows_before_aggregation Integer rows before aggregation (or `NULL`).
#' @param rows_after_aggregation Integer rows after aggregation (or `NULL`).
#' @return data.table with `layer_diagnostics` attribute.
#' @importFrom checkmate assert_data_frame assert_int assert_character
#'  assert_flag
attach_standardize_diagnostics <- function(
  standardized_dt,
  clean_rows_count,
  matched_count,
  unmatched_count,
  rules_count,
  rule_sources,
  aggregation_enabled = FALSE,
  rows_before_aggregation = NULL,
  rows_after_aggregation = NULL
) {
  checkmate::assert_data_frame(standardized_dt, min.rows = 0)
  checkmate::assert_int(clean_rows_count, lower = 0)
  checkmate::assert_int(matched_count, lower = 0)
  checkmate::assert_int(unmatched_count, lower = 0)
  checkmate::assert_int(rules_count, lower = 0)
  checkmate::assert_character(rule_sources, any.missing = FALSE)
  checkmate::assert_flag(aggregation_enabled)

  diagnostics_audit_dt <- if (matched_count > 0L) {
    data.table::data.table(affected_rows = as.integer(matched_count))
  } else {
    data.table::data.table(affected_rows = integer(0))
  }

  diagnostics <- build_layer_diagnostics(
    layer_name = "standardize_units",
    rows_in = clean_rows_count,
    rows_out = nrow(standardized_dt),
    audit_dt = diagnostics_audit_dt
  )

  diagnostics$unmatched_count <- as.integer(unmatched_count)
  diagnostics$applied_rules <- as.integer(rules_count)
  diagnostics$rule_sources <- unique(rule_sources)

  diagnostics$aggregation_enabled <- aggregation_enabled
  if (aggregation_enabled && !is.null(rows_before_aggregation)) {
    diagnostics$rows_before_aggregation <- as.integer(rows_before_aggregation)
    diagnostics$rows_after_aggregation <- as.integer(rows_after_aggregation)
    diagnostics$collapsed_rows_count <- as.integer(
      rows_before_aggregation - rows_after_aggregation
    )
    diagnostics$aggregated_groups_count <- as.integer(rows_after_aggregation)
  }

  if (rules_count == 0L) {
    diagnostics$messages <- "no numeric standardization rules found"
    diagnostics$potential_warnings <- diagnostics$messages
  } else {
    diagnostics$potential_warnings <- character(0)
  }

  attr(standardized_dt, "layer_diagnostics") <- list(
    standardize_units = diagnostics
  )

  return(standardized_dt)
}
