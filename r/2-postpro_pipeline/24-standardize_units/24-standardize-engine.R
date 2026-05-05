apply_standardize_rules <- function(
  mapped_dt,
  prepared_rules_dt,
  unit_column,
  value_column,
  commodity_column
) {
  checkmate::assert_data_frame(mapped_dt, min.rows = 0)
  checkmate::assert_data_frame(prepared_rules_dt, min.rows = 0)
  checkmate::assert_string(unit_column, min.chars = 1)
  checkmate::assert_string(value_column, min.chars = 1)
  checkmate::assert_string(commodity_column, min.chars = 1)

  if (data.table::is.data.table(mapped_dt)) {
    normalize_dt <- data.table::copy(mapped_dt)
  } else {
    normalize_dt <- data.table::as.data.table(mapped_dt)
  }

  if (!unit_column %in% names(normalize_dt)) {
    cli::cli_abort("unit column {.val {unit_column}} is missing")
  }
  if (!value_column %in% names(normalize_dt)) {
    cli::cli_abort("value column {.val {value_column}} is missing")
  }
  if (!commodity_column %in% names(normalize_dt)) {
    cli::cli_abort("commodity column {.val {commodity_column}} is missing")
  }

  numeric_values <- coerce_numeric_safe(normalize_dt[[value_column]])

  raw_value_input <- normalize_dt[[value_column]]
  blank_string_mask <- rep(FALSE, length(raw_value_input))

  if (is.character(raw_value_input)) {
    blank_string_mask <- !is.na(raw_value_input) & trimws(raw_value_input) == ""
  }

  invalid_mask <-
    !is.na(raw_value_input) &
    !blank_string_mask &
    is.na(numeric_values)

  if (any(invalid_mask)) {
    invalid_values <- unique(as.character(normalize_dt[[value_column]][
      invalid_mask
    ]))
    cli::cli_abort(
      "value column contains non-numeric values that cannot be standardized: {paste(invalid_values, collapse = ', ')}"
    )
  }

  unit_keys <- normalize_string(normalize_dt[[unit_column]])

  # Detect numeric-prefix multipliers in unit strings (e.g. "1000 head") and
  # materialize their effect on the numeric values so rules can be defined
  # only for the base unit (e.g. "head"). We only apply the multiplier when
  # a finite numeric prefix is found and not equal to 1.
  raw_unit_strings <- as.character(normalize_dt[[unit_column]])
  multiplier_prefix_pattern <- "^(\\s*[0-9][0-9.,]*(?:[eE][+-]?[0-9]+)?)[ _-]+(.+)$"

  detected_prefixes <- rep(1, nrow(normalize_dt))
  original_unit_strings <- raw_unit_strings

  # Vectorized extraction of numeric-prefix and base unit using stringi
  if (any(!is.na(raw_unit_strings) & nzchar(raw_unit_strings))) {
    matches_mat <- stringi::stri_match_first_regex(
      raw_unit_strings,
      multiplier_prefix_pattern
    )

    # matches_mat columns: full match, group1 (number), group2 (base unit)
    num_str_vec <- matches_mat[, 2]
    base_unit_vec <- matches_mat[, 3]

    valid_mask <- !is.na(num_str_vec) & nzchar(num_str_vec)
    if (any(valid_mask)) {
      # Clean numeric strings and coerce
      num_clean_vec <- gsub(",", "", num_str_vec[valid_mask])
      num_clean_vec <- trimws(num_clean_vec)
      num_val_vec <- suppressWarnings(as.numeric(num_clean_vec))

      apply_mask <- valid_mask
      apply_mask[apply_mask] <- !is.na(num_val_vec) & is.finite(num_val_vec) & (num_val_vec != 1)

      if (any(apply_mask)) {
        idxs <- which(apply_mask)

        # numeric multipliers aligned with idxs
        num_vals_aligned <- rep(NA_real_, length(idxs))
        num_vals_aligned[] <- as.numeric(gsub(",", "", trimws(num_str_vec[apply_mask])))

        numeric_values[idxs] <- numeric_values[idxs] * num_vals_aligned
        detected_prefixes[idxs] <- num_vals_aligned

        unit_keys[idxs] <- normalize_string(base_unit_vec[idxs])
        normalize_dt[[unit_column]][idxs] <- trimws(base_unit_vec[idxs])
      }
    }
  }

  if (nrow(prepared_rules_dt) == 0L) {
    normalize_dt[, (value_column) := numeric_values]

    empty_matched_rule_counts_dt <- data.table::data.table(
      rule_commodity_match_key = character(),
      applied_commodity_match_key = character(),
      unit_source_key = character(),
      affected_rows = integer()
    )

    return(list(
      data = normalize_dt,
      matched_count = 0L,
      unmatched_count = as.integer(sum(!is.na(unit_keys) & nzchar(unit_keys))),
      matched_rule_counts = empty_matched_rule_counts_dt
    ))
  }

  commodity_keys <- normalize_string(normalize_dt[[commodity_column]])

  # Stage 1: Try specific commodity matches
  join_input <- data.table::data.table(
    commodity_match_key = commodity_keys,
    unit_source_key = unit_keys
  )
  join_result <- prepared_rules_dt[
    join_input,
    .(
      commodity_match_key,
      unit_source_key,
      unit_target,
      unit_factor_num,
      unit_offset_num
    )
  ]

  is_matched <- !is.na(join_result$unit_target)

  # Stage 2: For unmatched rows with valid units, try "all commodity" fallback
  unmatched_with_unit <- !is_matched & !is.na(unit_keys) & nzchar(unit_keys)
  if (any(unmatched_with_unit)) {
    unmatched_idx <- which(unmatched_with_unit)

    fallback_join_input <- data.table::data.table(
      commodity_match_key = "all commodity",
      unit_source_key = unit_keys[unmatched_idx]
    )

    fallback_result <- prepared_rules_dt[
      fallback_join_input,
      .(
        commodity_match_key,
        unit_source_key,
        unit_target,
        unit_factor_num,
        unit_offset_num
      )
    ]

    matched_fallback <- !is.na(fallback_result$unit_target)

    if (any(matched_fallback)) {
      fallback_matched_idx <- unmatched_idx[matched_fallback]

      join_result[
        fallback_matched_idx,
        commodity_match_key := fallback_result$commodity_match_key[
          matched_fallback
        ]
      ]
      join_result[
        fallback_matched_idx,
        unit_source_key := fallback_result$unit_source_key[matched_fallback]
      ]
      join_result[
        fallback_matched_idx,
        unit_target := fallback_result$unit_target[matched_fallback]
      ]
      join_result[
        fallback_matched_idx,
        unit_factor_num := fallback_result$unit_factor_num[
          matched_fallback
        ]
      ]
      join_result[
        fallback_matched_idx,
        unit_offset_num := fallback_result$unit_offset_num[matched_fallback]
      ]

      is_matched[fallback_matched_idx] <- TRUE
    }
  }

  if (any(is_matched)) {
    matched_index <- which(is_matched)

    numeric_values[matched_index] <-
      numeric_values[matched_index] *
      join_result$unit_factor_num[matched_index] +
      join_result$unit_offset_num[matched_index]

    data.table::set(
      normalize_dt,
      i = matched_index,
      j = unit_column,
      value = join_result$unit_target[matched_index]
    )
  }

  normalize_dt[, (value_column) := numeric_values]

  unmatched_count <- sum(!is_matched & !is.na(unit_keys) & nzchar(unit_keys))

  matched_rule_counts_dt <- if (any(is_matched)) {
    data.table::data.table(
      rule_commodity_match_key = join_result$commodity_match_key[is_matched],
      applied_commodity_match_key = commodity_keys[is_matched],
      unit_source_key = join_result$unit_source_key[is_matched],
      original_unit = original_unit_strings[is_matched],
      rule_multiplier = join_result$unit_factor_num[is_matched],
      detected_prefix = detected_prefixes[is_matched]
    )[,
      .(
        affected_rows = .N,
        # effective multiplier applied to the original input value
        effective_multiplier = unique(rule_multiplier * detected_prefix)
      ),
      by = .(
        rule_commodity_match_key,
        applied_commodity_match_key,
        unit_source_key,
        original_unit,
        rule_multiplier,
        detected_prefix
      )
    ]
  } else {
    data.table::data.table(
      rule_commodity_match_key = character(),
      applied_commodity_match_key = character(),
      unit_source_key = character(),
      affected_rows = integer()
    )
  }

  return(list(
    data = normalize_dt,
    matched_count = as.integer(sum(is_matched)),
    unmatched_count = as.integer(unmatched_count),
    matched_rule_counts = matched_rule_counts_dt
  ))
}

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

#' @title Build standardize layer audit table
#' @description Creates a deterministic audit table aligned with the
#' standardization workbook rule schema.
#' @param layer_rules_dt Prepared standardization rule table.
#' @param matched_rule_counts_dt Rule-level matched row counts keyed by
#' `rule_commodity_match_key`, `applied_commodity_match_key`, and `unit_source_key`.
#' @param source_paths Character vector of source rule file paths.
#' @return `data.table` with standardize audit columns.
#' @importFrom checkmate assert_data_frame assert_character
