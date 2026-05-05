apply_target_updates_with_strategy <- function(
  dataset_dt,
  target_updates,
  target_column,
  row_id_column = "row_id",
  value_column = "value_target_result",
  condition_column = "value_target_raw",
  order_columns = character(0),
  apply_condition_match = TRUE,
  dataset_name,
  execution_stage,
  rule_file_identifier,
  source_column
) {
  checkmate::assert_data_table(dataset_dt)
  checkmate::assert_data_frame(target_updates, min.rows = 0)
  checkmate::assert_string(target_column, min.chars = 1)
  checkmate::assert_string(row_id_column, min.chars = 1)
  checkmate::assert_string(value_column, min.chars = 1)
  checkmate::assert_string(condition_column, min.chars = 1)
  checkmate::assert_character(order_columns, any.missing = FALSE)
  checkmate::assert_flag(apply_condition_match)
  checkmate::assert_string(dataset_name, min.chars = 1)
  checkmate::assert_string(execution_stage, min.chars = 1)
  checkmate::assert_string(rule_file_identifier, min.chars = 1)
  checkmate::assert_string(source_column, min.chars = 1)

  empty_events <- empty_last_rule_wins_overwrite_events_dt()

  if (nrow(target_updates) == 0L) {
    return(list(
      applied = FALSE,
      overwrite_events = empty_events,
      changed_value_count = 0L
    ))
  }

  if (!(target_column %in% colnames(dataset_dt))) {
    cli::cli_abort(
      "target column {.val {target_column}} is missing in dataset"
    )
  }

  updates_dt <- data.table::as.data.table(data.table::copy(target_updates))

  required_columns <- c(row_id_column, value_column, condition_column)
  missing_columns <- setdiff(required_columns, colnames(updates_dt))

  if (length(missing_columns) > 0L) {
    cli::cli_abort(c(
      "target updates are missing required columns.",
      "x" = paste(missing_columns, collapse = ", ")
    ))
  }

  present_order_columns <- intersect(order_columns, colnames(updates_dt))
  if (length(present_order_columns) > 0L) {
    data.table::setorderv(updates_dt, cols = present_order_columns)
  }

  updates_dt[, row_id_internal := as.integer(get(row_id_column))]
  updates_dt <- updates_dt[!is.na(row_id_internal)]

  if (nrow(updates_dt) == 0L) {
    return(list(
      applied = FALSE,
      overwrite_events = empty_events,
      changed_value_count = 0L
    ))
  }

  out_of_bounds_mask <-
    updates_dt$row_id_internal < 1L |
    updates_dt$row_id_internal > nrow(dataset_dt)

  if (any(out_of_bounds_mask)) {
    cli::cli_abort(
      "target updates contain row indexes outside dataset boundaries"
    )
  }

  strategy_config <- get_target_update_strategy_config()
  tokenized_target_condition_columns <- resolve_tokenized_target_condition_columns(
    strategy_config = strategy_config
  )

  if (isTRUE(apply_condition_match)) {
    has_condition <- !is.na(updates_dt[[condition_column]])
    if (any(has_condition)) {
      conditioned_updates_raw <- updates_dt[has_condition]
      current_values <- dataset_dt[[target_column]][
        conditioned_updates_raw$row_id_internal
      ]
      condition_matches <- match_rule_target_condition_values(
        current_values = current_values,
        condition_values = conditioned_updates_raw[[condition_column]],
        tokenized_target = target_column %in% tokenized_target_condition_columns
      )

      conditioned_updates <- conditioned_updates_raw[condition_matches]

      is_wildcard_condition <- !is.na(conditioned_updates[[condition_column]]) &
        trimws(as.character(conditioned_updates[[condition_column]])) ==
          strategy_config$rule_match_wildcard_token

      if (any(is_wildcard_condition)) {
        wildcard_idx <- which(is_wildcard_condition)
        wildcard_current_values <- dataset_dt[[target_column]][
          conditioned_updates$row_id_internal[wildcard_idx]
        ]
        wildcard_candidate_values <- conditioned_updates[[value_column]][
          wildcard_idx
        ]

        wildcard_value_already_present <- match_rule_target_condition_values(
          current_values = wildcard_current_values,
          condition_values = wildcard_candidate_values,
          tokenized_target = target_column %in%
            tokenized_target_condition_columns
        )

        if (any(wildcard_value_already_present)) {
          conditioned_updates <- conditioned_updates[
            -wildcard_idx[wildcard_value_already_present]
          ]
        }
      }

      unconditional_updates <- updates_dt[!has_condition]

      updates_dt <- data.table::rbindlist(
        list(unconditional_updates, conditioned_updates),
        use.names = TRUE,
        fill = TRUE
      )
    }
  }

  if (nrow(updates_dt) == 0L) {
    return(list(
      applied = FALSE,
      overwrite_events = empty_events,
      changed_value_count = 0L
    ))
  }

  strategy <- resolve_target_update_strategy(
    target_column = target_column,
    strategy_config = strategy_config
  )

  if (identical(strategy, "last_rule_wins")) {
    updates_dt[, update_value := as.character(get(value_column))]

    use_unique_row_fast_path <-
      resolve_last_rule_wins_unique_row_fast_path_enabled() &&
      data.table::uniqueN(updates_dt$row_id_internal) == nrow(updates_dt)

    if (use_unique_row_fast_path) {
      previous_values <- dataset_dt[[target_column]][updates_dt$row_id_internal]

      data.table::set(
        dataset_dt,
        i = updates_dt$row_id_internal,
        j = target_column,
        value = updates_dt$update_value
      )

      changed_value_count <- count_elementwise_value_changes(
        before_values = previous_values,
        after_values = dataset_dt[[target_column]][updates_dt$row_id_internal]
      )

      return(list(
        applied = TRUE,
        overwrite_events = empty_events,
        changed_value_count = changed_value_count
      ))
    }

    updates_collapsed <- updates_dt[,
      .(
        update_value = update_value[.N],
        candidate_count = .N,
        unique_candidate_count = data.table::uniqueN(update_value),
        candidate_values = paste(update_value, collapse = "; ")
      ),
      by = .(row_id_internal)
    ]

    overwrite_events <- updates_collapsed[
      candidate_count > 1L & unique_candidate_count > 1L,
      .(
        dataset_name = dataset_name,
        execution_stage = execution_stage,
        rule_file_identifier = rule_file_identifier,
        column_source = source_column,
        column_target = target_column,
        row_id = as.integer(row_id_internal),
        candidate_count = as.integer(candidate_count),
        unique_candidate_count = as.integer(unique_candidate_count),
        selected_value = as.character(update_value),
        candidate_values = as.character(candidate_values)
      )
    ]

    previous_values <- dataset_dt[[target_column]][
      updates_collapsed$row_id_internal
    ]

    data.table::set(
      dataset_dt,
      i = updates_collapsed$row_id_internal,
      j = target_column,
      value = updates_collapsed$update_value
    )

    changed_value_count <- count_elementwise_value_changes(
      before_values = previous_values,
      after_values = dataset_dt[[target_column]][
        updates_collapsed$row_id_internal
      ]
    )

    return(list(
      applied = TRUE,
      overwrite_events = overwrite_events,
      changed_value_count = changed_value_count
    ))
  }

  if (identical(strategy, "concatenate")) {
    target_vector <- dataset_dt[[target_column]]
    if (!(is.character(target_vector) || is.factor(target_vector))) {
      cli::cli_abort(c(
        "concatenate strategy requires a character-like target column.",
        "x" = paste0(
          "column ",
          target_column,
          " has class: ",
          paste(class(target_vector), collapse = ", ")
        )
      ))
    }

    updates_dt[, update_value := as.character(get(value_column))]
    updates_dt[trimws(update_value) == "", update_value := NA_character_]
    updates_dt <- updates_dt[!is.na(update_value)]

    if (nrow(updates_dt) == 0L) {
      return(list(
        applied = FALSE,
        overwrite_events = empty_events,
        changed_value_count = 0L
      ))
    }

    delimiter <- strategy_config$concatenate_delimiter

    updates_collapsed <- updates_dt[,
      .(update_value = paste(update_value, collapse = delimiter)),
      by = .(row_id_internal)
    ]

    existing_values <- dataset_dt[[target_column]][
      updates_collapsed$row_id_internal
    ]
    merged_values <- concatenate_existing_and_incoming_values(
      existing_values = existing_values,
      incoming_values = updates_collapsed$update_value,
      delimiter = delimiter
    )

    data.table::set(
      dataset_dt,
      i = updates_collapsed$row_id_internal,
      j = target_column,
      value = merged_values
    )

    changed_value_count <- count_elementwise_value_changes(
      before_values = existing_values,
      after_values = dataset_dt[[target_column]][
        updates_collapsed$row_id_internal
      ]
    )

    return(list(
      applied = TRUE,
      overwrite_events = empty_events,
      changed_value_count = changed_value_count
    ))
  }

  cli::cli_abort(
    "unhandled target-update strategy {.val {strategy}} for {.val {target_column}}"
  )
}

#' @title Apply one conditional dictionary group
#' @description Executes vectorized matching and mutation for one
#' `(column_source, column_target)` group and captures structured audit records.
#' @param dataset_dt Data table to mutate.
#' @param group_rules Canonical rules for one source-target column pair.
#' @param stage_name Character scalar stage label.
#' @param dataset_name Character scalar dataset identifier.
#' @param rule_file_id Character scalar rule file identifier.
#' @param execution_timestamp_utc Character scalar execution timestamp.
#' @return List with mutated `data` and `audit` table.
#' @importFrom checkmate assert_data_table assert_data_frame assert_string
apply_conditional_rule_group <- function(
  dataset_dt,
  group_rules,
  stage_name,
  dataset_name,
  rule_file_id,
  execution_timestamp_utc,
  apply_match_normalization = TRUE
) {
  checkmate::assert_data_table(dataset_dt)
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

  target_condition_matches <- match_rule_target_condition_values(
    current_values = target_values_pre_update[joined_dt$row_id],
    condition_values = joined_dt$value_target_raw,
    tokenized_target = target_column %in% tokenized_target_condition_columns,
    apply_match_normalization = apply_target_condition_normalization
  )

  matched_row_mask <- !is.na(joined_dt$column_source) & target_condition_matches
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

  matched_counts <- joined_dt[
    matched_row_mask,
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

#' @title Apply footnote rules with multi-footnote split-join-reconstruct
#' @description Vectorized footnotes processing that splits semicolon-delimited
#' footnotes into long format, matches individual footnotes against rules,
#' applies replacements and removals, updates target columns from matched
#' footnotes, and reconstructs the footnotes column preserving original order.
#' @param dataset_dt Data table to mutate.
#' @param footnote_rules Canonical rules where `column_source == "footnotes"`.
#' @param stage_name Character scalar stage label.
#' @param dataset_name Character scalar dataset identifier.
#' @param rule_file_id Character scalar rule file identifier.
#' @param execution_timestamp_utc Character scalar execution timestamp.
#' @return List with mutated `data` and `audit` table compatible with
#' `apply_conditional_rule_group()` output schema.
#' @importFrom checkmate assert_data_table assert_data_frame assert_string
#' @importFrom data.table data.table as.data.table rbindlist setindex fcoalesce
