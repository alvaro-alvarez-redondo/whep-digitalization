# script: post-processing rule engine — conditional rule groups
# description: apply source->target conditional rule groups. Split from
# 23-target-apply.R (>500-line policy); pure function definitions, sourced
# together with the rest of the 23-postpro_rule_engine stage via
# source_postpro_scripts(), so load order within the stage is immaterial.

#' @title Prepare one conditional rule group
#' @description Coerces group rules to data.table and validates the stage name
#' for later application by `apply_conditional_rule_group()`.
#' @param group_rules Canonical rules for one source-target column pair.
#' @param stage_name Character scalar stage label.
#' @return Named list with `group_rules` and `stage_name`.
#' @importFrom checkmate assert_data_frame
prepare_conditional_rule_group <- function(group_rules, stage_name) {
  checkmate::assert_data_frame(group_rules, min.rows = 1)
  validated_stage_name <- validate_postpro_stage_name(stage_name)
  list(
    group_rules = data.table::as.data.table(group_rules),
    stage_name = validated_stage_name
  )
}

apply_conditional_rule_group <- function(
  dataset_dt,
  group_rules = NULL,
  stage_name,
  dataset_name,
  rule_file_id,
  execution_timestamp_utc,
  apply_match_normalization = TRUE,
  prepared_group = NULL
) {
  checkmate::assert_data_table(dataset_dt)
  has_rules <- !is.null(group_rules)
  has_prepared <- !is.null(prepared_group)
  if (has_rules == has_prepared) {
    cli::cli_abort("exactly one of {.arg group_rules} or {.arg prepared_group} must be provided")
  }
  if (has_prepared) {
    group_rules <- prepared_group$group_rules
  }
  checkmate::assert_data_frame(group_rules, min.rows = 1)
  validated_stage_name <- validate_postpro_stage_name(stage_name)
  checkmate::assert_string(dataset_name, min.chars = 1)
  checkmate::assert_string(rule_file_id, min.chars = 1)
  checkmate::assert_string(execution_timestamp_utc, min.chars = 1)
  checkmate::assert_flag(apply_match_normalization)

  target_value_column <- get_stage_target_value_column(validated_stage_name)
  source_value_column <- get_stage_source_value_column(validated_stage_name)
  rule_match_normalization_settings <- resolve_rule_match_normalization_settings()
  excluded_columns <- rule_match_normalization_settings$excluded_columns

  group_dt <- data.table::as.data.table(group_rules)
  source_value_column_present <- source_value_column %in% names(group_dt)

  if (!(source_value_column %in% names(group_dt))) {
    group_dt[, (source_value_column) := NA_character_]
  }

  if (!("source_value_column_present" %in% names(group_dt))) {
    group_dt[, source_value_column_present := source_value_column_present]
  }

  source_column <- group_dt$column_source[[1]]
  target_column <- group_dt$column_target[[1]]
  apply_source_match_normalization <-
    isTRUE(apply_match_normalization) && !(source_column %in% excluded_columns)
  apply_target_condition_normalization <-
    isTRUE(apply_match_normalization) && !(target_column %in% excluded_columns)

  normalize_rules <- unique(group_dt[, .(
    column_source,
    value_source_raw,
    source_value_raw = get(source_value_column),
    source_value_column_present,
    column_target,
    value_target_raw,
    value_target_result_encoded = encode_target_rule_value(get(
      target_value_column
    )),
    source_key = encode_rule_match_key(
      value_source_raw,
      apply_normalization = apply_source_match_normalization
    ),
    target_key = encode_rule_match_key(
      value_target_raw,
      apply_normalization = apply_target_condition_normalization
    )
  )][,
    `:=`(
      value_source_result = as.character(source_value_raw),
      value_target_result = decode_target_rule_value(
        value_target_result_encoded
      )
    )
  ])

  normalize_rules[
    trimws(value_source_result) == "",
    value_source_result := NA_character_
  ]

  data.table::setindex(normalize_rules, source_key)

  tokenized_target_condition_columns <- resolve_tokenized_target_condition_columns(
    strategy_config = get_target_update_strategy_config()
  )

  source_values_pre_update <- dataset_dt[[source_column]]
  target_values_pre_update <- dataset_dt[[target_column]]

  join_input <- data.table::data.table(
    row_id = seq_len(nrow(dataset_dt)),
    source_key = encode_rule_match_key(
      source_values_pre_update,
      apply_normalization = apply_source_match_normalization
    )
  )

  joined_dt <- normalize_rules[
    join_input,
    on = .(source_key),
    allow.cartesian = TRUE
  ]

  # `matched_row_mask` ANDs the source-key match with the target-condition match,
  # so the (normalization-heavy) condition match is only consequential for rows
  # that already matched a rule on the source key. Restricting it to those rows
  # is equivalent and skips normalizing target/condition values for the unmatched
  # majority of the joined table.
  source_matched_mask <- !is.na(joined_dt$column_source)
  target_condition_matches <- logical(length(source_matched_mask))
  if (any(source_matched_mask)) {
    matched_row_ids <- joined_dt$row_id[source_matched_mask]
    target_condition_matches[source_matched_mask] <-
      match_rule_target_condition_values(
        current_values = target_values_pre_update[matched_row_ids],
        condition_values = joined_dt$value_target_raw[source_matched_mask],
        tokenized_target = target_column %in% tokenized_target_condition_columns,
        apply_match_normalization = apply_target_condition_normalization
      )
  }

  matched_row_mask <- source_matched_mask & target_condition_matches
  source_update_mask <- matched_row_mask &
    !is.na(joined_dt$source_value_column_present) &
    as.logical(joined_dt$source_value_column_present)
  matched_rows <- as.integer(sum(matched_row_mask))
  overwrite_events_dt <- empty_last_rule_wins_overwrite_events_dt()
  source_changed_value_count <- 0L
  target_changed_value_count <- 0L

  if (matched_rows > 0L) {
    if (any(source_update_mask)) {
      source_row_ids <- joined_dt$row_id[source_update_mask]
      source_values_before <- dataset_dt[[source_column]][source_row_ids]

      data.table::set(
        dataset_dt,
        i = source_row_ids,
        j = source_column,
        value = joined_dt$value_source_result[source_update_mask]
      )

      source_changed_value_count <- count_elementwise_value_changes(
        before_values = source_values_before,
        after_values = dataset_dt[[source_column]][source_row_ids]
      )
    }

    target_updates <- joined_dt[
      matched_row_mask,
      .(
        row_id,
        value_target_raw,
        value_target_result
      )
    ]

    update_result <- apply_target_updates_with_strategy(
      dataset_dt = dataset_dt,
      target_updates = target_updates,
      target_column = target_column,
      row_id_column = "row_id",
      value_column = "value_target_result",
      condition_column = "value_target_raw",
      order_columns = c("row_id"),
      apply_condition_match = FALSE,
      dataset_name = dataset_name,
      execution_stage = validated_stage_name,
      rule_file_identifier = rule_file_id,
      source_column = source_column
    )

    overwrite_events_dt <- update_result$overwrite_events
    target_changed_value_count <- update_result$changed_value_count
  }

  audit_mask <- if (source_changed_value_count + target_changed_value_count == 0L) {
    rep(FALSE, length(matched_row_mask))
  } else {
    matched_row_mask
  }

  matched_counts <- joined_dt[
    audit_mask,
    .(
      affected_rows = .N
    ),
    by = .(
      source_key,
      target_key,
      value_source_result,
      value_target_result_encoded
    )
  ]

  audit_dt <- normalize_rules[
    matched_counts,
    on = .(
      source_key,
      target_key,
      value_source_result,
      value_target_result_encoded
    )
  ][,
    .(
      dataset_name = dataset_name,
      column_source,
      value_source_raw,
      value_source_result,
      column_target,
      value_target_raw,
      value_target_result,
      affected_rows = data.table::fcoalesce(affected_rows, 0L),
      execution_timestamp_utc = execution_timestamp_utc,
      rule_file_identifier = rule_file_id,
      execution_stage = validated_stage_name
    )
  ][order(column_source, column_target, value_source_raw, value_target_raw)]

  return(list(
    data = dataset_dt,
    audit = audit_dt,
    overwrite_events = overwrite_events_dt,
    changed_value_count = as.integer(
      source_changed_value_count + target_changed_value_count
    )
  ))
}
