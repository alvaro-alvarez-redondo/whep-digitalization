# script: standardize units — engine
# description: apply_standardize_rules, the core unit-conversion engine.
#
# The post-standardization aggregation helpers were split into the sibling
# 24-standardize-aggregation.R (>500-line policy). Under the normal glob
# sourcing (source_postpro_scripts) that sibling loads first — it sorts before
# this file — so the guard below is a no-op there. It fires only when this file
# is sourced standalone via an explicit path list, notably the read-only perf
# harness perf/perf_pipeline/p9-orchestration.R (which lists
# 24-standardize-engine.R but not its sibling), keeping the aggregation
# functions available in that context too.
if (!exists("aggregate_standardized_rows", mode = "function", inherits = TRUE)) {
  source(
    here::here(
      "r", "2-postpro_pipeline", "24-standardize_units",
      "24-standardize-aggregation.R"
    ),
    local = FALSE
  )
}

#' Apply unit standardization rules to a dataset
#' Converts numeric values based on unit standardization rules, handling
#' numeric-prefix multipliers in unit strings and falling back to an
#' `"all commodity"` generic rule when no specific match exists.
#' @param mapped_dt `data.frame`/`data.table` to standardize.
#' @param prepared_rules_dt `data.frame`/`data.table` of prepared standardization
#'   rules.
#' @param unit_column Character scalar name of the unit column.
#' @param value_column Character scalar name of the numeric value column.
#' @param commodity_column Character scalar name of the commodity column.
#' @return Named list with `data` (standardized `data.table`), `matched_count`,
#'   `unmatched_count`, and `matched_rule_counts`.
#' @examples
#' \dontrun{
#' apply_standardize_rules(dataset_dt, rules_dt, "unit", "value", "commodity")
#' }
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
  source_unit_raw_strings <- raw_unit_strings

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
      apply_mask[apply_mask] <- !is.na(num_val_vec) &
        is.finite(num_val_vec) &
        (num_val_vec != 1)

      if (any(apply_mask)) {
        idxs <- which(apply_mask)

        # numeric multipliers aligned with idxs
        num_vals_aligned <- rep(NA_real_, length(idxs))
        num_vals_aligned[] <- as.numeric(gsub(
          ",",
          "",
          trimws(num_str_vec[apply_mask])
        ))

        numeric_values[idxs] <- numeric_values[idxs] * num_vals_aligned
        detected_prefixes[idxs] <- num_vals_aligned

        unit_keys[idxs] <- normalize_string(base_unit_vec[idxs])
        normalize_dt[[unit_column]][idxs] <- trimws(base_unit_vec[idxs])
      }
    }
  }

  if (nrow(prepared_rules_dt) > 0L) {
    commodity_keys <- normalize_string(normalize_dt[[commodity_column]])

    prefix_applied_mask <- detected_prefixes != 1
    if (any(prefix_applied_mask)) {
      original_keys <- normalize_string(source_unit_raw_strings)
      prefix_idx <- which(prefix_applied_mask)

      # A prefixed unit (e.g. "1000 egg") is reverted to its original,
      # undecomposed form only when a rule can actually match the row in that
      # form: either a commodity-specific rule or the "all commodity" fallback
      # keyed on the original unit. Reverting merely because the original unit
      # string appears under some *other* commodity would strand this row as
      # unmatched, even when its decomposed base unit ("egg") has a specific or
      # fallback rule that would otherwise apply. The check therefore mirrors
      # the two-stage match below (specific commodity, then "all commodity").
      specific_revert_lookup <- data.table::data.table(
        commodity_match_key = commodity_keys[prefix_idx],
        unit_source_key = original_keys[prefix_idx]
      )
      fallback_revert_lookup <- data.table::data.table(
        commodity_match_key = "all commodity",
        unit_source_key = original_keys[prefix_idx]
      )

      revert_matches <-
        !is.na(prepared_rules_dt[specific_revert_lookup, unit_target]) |
        !is.na(prepared_rules_dt[fallback_revert_lookup, unit_target])

      if (any(revert_matches)) {
        revert_idx <- prefix_idx[revert_matches]
        unit_keys[revert_idx] <- original_keys[revert_idx]
        numeric_values[revert_idx] <- coerce_numeric_safe(
          normalize_dt[[value_column]]
        )[revert_idx]
        detected_prefixes[revert_idx] <- 1
        data.table::set(
          normalize_dt, i = revert_idx, j = unit_column,
          value = raw_unit_strings[revert_idx]
        )
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
      source_unit_raw = source_unit_raw_strings[is_matched],
      rule_multiplier = join_result$unit_factor_num[is_matched],
      detected_prefix = detected_prefixes[is_matched]
    )[,
      .(
        affected_rows = .N,
        # effective multiplier applied to the original input value
        unit_factor_effective = unique(rule_multiplier * detected_prefix)
      ),
      by = .(
        rule_commodity_match_key,
        applied_commodity_match_key,
        unit_source_key,
        source_unit_raw,
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
