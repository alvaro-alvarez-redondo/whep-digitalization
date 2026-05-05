apply_footnote_rules <- function(
  dataset_dt,
  footnote_rules,
  stage_name,
  dataset_name,
  rule_file_id,
  execution_timestamp_utc,
  apply_match_normalization = TRUE
) {
  checkmate::assert_data_table(dataset_dt)
  checkmate::assert_data_frame(footnote_rules, min.rows = 1)
  validated_stage_name <- validate_postpro_stage_name(stage_name)
  checkmate::assert_string(dataset_name, min.chars = 1)
  checkmate::assert_string(rule_file_id, min.chars = 1)
  checkmate::assert_string(execution_timestamp_utc, min.chars = 1)
  checkmate::assert_flag(apply_match_normalization)

  source_value_column <- get_stage_source_value_column(validated_stage_name)
  target_value_column <- get_stage_target_value_column(validated_stage_name)
  rule_match_normalization_settings <- resolve_rule_match_normalization_settings()
  excluded_columns <- rule_match_normalization_settings$excluded_columns
  footnote_source_normalization <-
    isTRUE(apply_match_normalization) && !("footnotes" %in% excluded_columns)

  # --- ensure footnotes column exists -----------------------------------------
  if (!("footnotes" %in% colnames(dataset_dt))) {
    dataset_dt[, footnotes := NA_character_]
  }

  footnote_values_before <- dataset_dt$footnotes

  # --- step 1: assign row identifiers ----------------------------------------
  dataset_dt[, row_id := .I]
  n_rows <- nrow(dataset_dt)

  # --- step 2: split footnotes by ";" into long format -----------------------
  fn_long <- dataset_dt[,
    .(
      footnote_raw = unlist(strsplit(
        as.character(footnotes),
        ";",
        fixed = TRUE
      )),
      footnote_index = seq_along(unlist(strsplit(
        as.character(footnotes),
        ";",
        fixed = TRUE
      )))
    ),
    by = row_id
  ]
  fn_long[, footnote := trimws(footnote_raw)]
  fn_long[trimws(footnote) == "", footnote := NA_character_]

  # handle rows with NA footnotes (no split produces empty result)
  na_rows <- dataset_dt[is.na(footnotes), .(row_id)]
  if (nrow(na_rows) > 0L) {
    na_long <- data.table::data.table(
      row_id = na_rows$row_id,
      footnote_raw = NA_character_,
      footnote_index = 1L,
      footnote = NA_character_
    )
    fn_long <- data.table::rbindlist(list(fn_long, na_long), use.names = TRUE)
    data.table::setkey(fn_long, row_id, footnote_index)
  }

  # --- step 3: normalize rules and build match keys --------------------------
  rules_dt <- data.table::as.data.table(footnote_rules)
  normalize_rules <- unique(rules_dt[, .(
    column_source = "footnotes",
    value_source_raw,
    source_value_raw = get(source_value_column),
    column_target,
    value_target_raw,
    value_target_result_encoded = encode_target_rule_value(get(
      target_value_column
    )),
    source_key = encode_rule_match_key(
      value_source_raw,
      apply_normalization = footnote_source_normalization
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

  # --- step 4: join footnotes with rules on source key -----------------------
  fn_long[,
    source_key := encode_rule_match_key(
      footnote,
      apply_normalization = footnote_source_normalization
    )
  ]
  joined <- normalize_rules[
    fn_long,
    on = .(source_key),
    allow.cartesian = TRUE
  ]

  # --- step 5: compute footnote_final using vectorized conditional logic -----
  matched_mask <- !is.na(joined$column_source)

  conditional_target_mask <- matched_mask &
    joined$column_target != "footnotes" &
    !is.na(joined$value_target_raw)

  if (any(conditional_target_mask)) {
    condition_match_mask <- rep(FALSE, nrow(joined))

    tokenized_target_condition_columns <- resolve_tokenized_target_condition_columns(
      strategy_config = get_target_update_strategy_config()
    )

    conditional_target_columns <- unique(joined$column_target[
      conditional_target_mask
    ])

    for (target_column in conditional_target_columns) {
      target_column_mask <-
        conditional_target_mask & joined$column_target == target_column

      current_target_values <- dataset_dt[[target_column]][
        joined$row_id[target_column_mask]
      ]

      condition_match_mask[target_column_mask] <-
        match_rule_target_condition_values(
          current_values = current_target_values,
          condition_values = joined$value_target_raw[target_column_mask],
          tokenized_target = target_column %in%
            tokenized_target_condition_columns,
          apply_match_normalization = isTRUE(apply_match_normalization) &&
            !(target_column %in% excluded_columns)
        )
    }

    matched_mask <- matched_mask &
      (!conditional_target_mask | condition_match_mask)
  }

  joined[, footnote_final := footnote]

  # matched replacement: value_source_result is not NA → replace footnote text
  replace_mask <- matched_mask & !is.na(joined$value_source_result)
  if (any(replace_mask)) {
    joined[replace_mask, footnote_final := value_source_result]
  }

  # matched removal: value_source_result is NA → remove footnote
  remove_mask <- matched_mask & is.na(joined$value_source_result)
  if (any(remove_mask)) {
    joined[remove_mask, footnote_final := NA_character_]
  }

  joined[, `:=`(
    is_remove = remove_mask,
    is_replace = replace_mask
  )]

  # --- step 6: apply target column updates -----------------------------------
  target_updates <- joined[
    matched_mask & column_target != "footnotes",
    .(
      row_id,
      footnote_index,
      column_target,
      value_target_raw,
      value_target_result
    )
  ]
  overwrite_event_tables <- list()
  total_target_changed_value_count <- 0L

  if (nrow(target_updates) > 0L) {
    target_columns <- unique(target_updates$column_target)

    for (tc in target_columns) {
      update_result <- apply_target_updates_with_strategy(
        dataset_dt = dataset_dt,
        target_updates = target_updates[column_target == tc],
        target_column = tc,
        row_id_column = "row_id",
        value_column = "value_target_result",
        condition_column = "value_target_raw",
        order_columns = c("row_id", "footnote_index"),
        dataset_name = dataset_name,
        execution_stage = validated_stage_name,
        rule_file_identifier = rule_file_id,
        source_column = "footnotes"
      )

      if (nrow(update_result$overwrite_events) > 0L) {
        overwrite_event_tables[[length(overwrite_event_tables) + 1L]] <-
          update_result$overwrite_events
      }

      total_target_changed_value_count <-
        total_target_changed_value_count + update_result$changed_value_count
    }
  }

  overwrite_events_dt <- if (length(overwrite_event_tables) > 0L) {
    data.table::rbindlist(overwrite_event_tables, use.names = TRUE, fill = TRUE)
  } else {
    empty_last_rule_wins_overwrite_events_dt()
  }

  # --- step 7: reconstruct footnotes per row ---------------------------------
  # Resolve each token deterministically across cartesian duplicates:
  # remove beats replace, replace beats unchanged original token.
  token_resolution <- joined[,
    .(
      footnote_final = {
        if (any(is_remove, na.rm = TRUE)) {
          NA_character_
        } else if (any(is_replace, na.rm = TRUE)) {
          replacement_values <- footnote_final[
            is_replace & !is.na(footnote_final)
          ]
          if (length(replacement_values) == 0L) {
            NA_character_
          } else {
            replacement_values[[1L]]
          }
        } else {
          original_values <- footnote[!is.na(footnote)]
          if (length(original_values) == 0L) {
            NA_character_
          } else {
            original_values[[1L]]
          }
        }
      }
    ),
    by = .(row_id, footnote_index)
  ]
  data.table::setorder(token_resolution, row_id, footnote_index)
  reconstructed <- token_resolution[,
    .(
      footnotes_new = {
        valid <- footnote_final[!is.na(footnote_final)]
        if (length(valid) == 0L) {
          NA_character_
        } else {
          paste(valid, collapse = "; ")
        }
      }
    ),
    by = row_id
  ]

  # update footnotes in dataset
  dataset_dt[reconstructed, footnotes := i.footnotes_new, on = "row_id"]

  # rows without any footnote entries (should not happen, but safety net)
  missing_recon <- setdiff(seq_len(n_rows), reconstructed$row_id)
  if (length(missing_recon) > 0L) {
    data.table::set(
      dataset_dt,
      i = missing_recon,
      j = "footnotes",
      value = NA_character_
    )
  }

  # --- step 8: clean temporary columns ---------------------------------------
  dataset_dt[, row_id := NULL]

  footnote_changed_value_count <- count_elementwise_value_changes(
    before_values = footnote_values_before,
    after_values = dataset_dt$footnotes
  )

  # --- step 9: generate audit records ----------------------------------------
  audit_source <- joined[matched_mask]

  if (nrow(audit_source) > 0L) {
    source_audit <- audit_source[,
      .(affected_rows = .N),
      by = .(
        value_source_raw,
        value_source_result,
        column_target,
        value_target_raw,
        value_target_result
      )
    ]

    audit_dt <- source_audit[, .(
      dataset_name = dataset_name,
      column_source = "footnotes",
      value_source_raw,
      value_source_result,
      column_target,
      value_target_raw,
      value_target_result,
      affected_rows = as.integer(affected_rows),
      execution_timestamp_utc = execution_timestamp_utc,
      rule_file_identifier = rule_file_id,
      execution_stage = validated_stage_name
    )][order(column_source, column_target, value_source_raw, value_target_raw)]
  } else {
    audit_dt <- data.table::data.table(
      dataset_name = character(0),
      column_source = character(0),
      value_source_raw = character(0),
      value_source_result = character(0),
      column_target = character(0),
      value_target_raw = character(0),
      value_target_result = character(0),
      affected_rows = integer(0),
      execution_timestamp_utc = character(0),
      rule_file_identifier = character(0),
      execution_stage = character(0)
    )
  }

  return(list(
    data = dataset_dt,
    audit = audit_dt,
    overwrite_events = overwrite_events_dt,
    changed_value_count = as.integer(
      total_target_changed_value_count + footnote_changed_value_count
    )
  ))
}

#' @title Apply canonical rule file payload
#' @description Executes matching and mutation in deterministic group order for a
#' single file payload. Routes footnote-source rules through the specialized
#' `apply_footnote_rules()` handler for multi-footnote split-join processing.
#' @param dataset_dt Data table to mutate.
#' @param canonical_rules Canonical rules table.
#' @param stage_name Character scalar stage label.
#' @param dataset_name Character scalar dataset identifier.
#' @param rule_file_id Character scalar rule file identifier.
#' @param execution_timestamp_utc Character scalar execution timestamp.
#' @return List with mutated `data` and aggregated `audit` table.
#' @importFrom checkmate assert_data_table assert_data_frame assert_string
apply_rule_payload <- function(
  dataset_dt,
  canonical_rules,
  stage_name,
  dataset_name,
  rule_file_id,
  execution_timestamp_utc,
  apply_match_normalization = TRUE
) {
  checkmate::assert_data_table(dataset_dt)
  checkmate::assert_data_frame(canonical_rules, min.rows = 0)
  validated_stage_name <- validate_postpro_stage_name(stage_name)
  checkmate::assert_string(dataset_name, min.chars = 1)
  checkmate::assert_string(rule_file_id, min.chars = 1)
  checkmate::assert_string(execution_timestamp_utc, min.chars = 1)
  checkmate::assert_flag(apply_match_normalization)

  if (nrow(canonical_rules) == 0L) {
    return(list(
      data = dataset_dt,
      audit = data.table::data.table(),
      overwrite_events = empty_last_rule_wins_overwrite_events_dt(),
      changed_value_count = 0L
    ))
  }

  rules_dt <- data.table::as.data.table(canonical_rules)
  audit_tables <- list()
  overwrite_tables <- list()
  changed_value_count <- 0L
  current_data <- dataset_dt

  # --- route footnote-source rules through specialized handler ----------------
  footnote_mask <- rules_dt$column_source == "footnotes"
  footnote_rules <- rules_dt[footnote_mask]
  standard_rules <- rules_dt[!footnote_mask]

  if (nrow(footnote_rules) > 0L) {
    fn_result <- apply_footnote_rules(
      dataset_dt = current_data,
      footnote_rules = footnote_rules,
      stage_name = validated_stage_name,
      dataset_name = dataset_name,
      rule_file_id = rule_file_id,
      execution_timestamp_utc = execution_timestamp_utc,
      apply_match_normalization = apply_match_normalization
    )
    current_data <- fn_result$data
    audit_tables[[length(audit_tables) + 1L]] <- fn_result$audit
    changed_value_count <- changed_value_count + fn_result$changed_value_count
    if (nrow(fn_result$overwrite_events) > 0L) {
      overwrite_tables[[length(overwrite_tables) + 1L]] <-
        fn_result$overwrite_events
    }
  }

  # --- apply remaining standard rules via grouped execution -------------------
  grouped_dictionary <- build_conditional_rule_dictionary(
    standard_rules,
    validated_stage_name
  )

  if (length(grouped_dictionary) > 0L) {
    for (group_index in seq_len(length(grouped_dictionary))) {
      group_result <- apply_conditional_rule_group(
        dataset_dt = current_data,
        group_rules = grouped_dictionary[[group_index]],
        stage_name = validated_stage_name,
        dataset_name = dataset_name,
        rule_file_id = rule_file_id,
        execution_timestamp_utc = execution_timestamp_utc,
        apply_match_normalization = apply_match_normalization
      )

      current_data <- group_result$data
      audit_tables[[length(audit_tables) + 1L]] <- group_result$audit
      changed_value_count <-
        changed_value_count + group_result$changed_value_count
      if (nrow(group_result$overwrite_events) > 0L) {
        overwrite_tables[[length(overwrite_tables) + 1L]] <-
          group_result$overwrite_events
      }
    }
  }

  combined_audit <- data.table::rbindlist(
    audit_tables,
    use.names = TRUE,
    fill = TRUE
  )

  combined_overwrite_events <- if (length(overwrite_tables) > 0L) {
    data.table::rbindlist(overwrite_tables, use.names = TRUE, fill = TRUE)
  } else {
    empty_last_rule_wins_overwrite_events_dt()
  }

  return(list(
    data = current_data,
    audit = combined_audit,
    overwrite_events = combined_overwrite_events,
    changed_value_count = as.integer(changed_value_count)
  ))
}
