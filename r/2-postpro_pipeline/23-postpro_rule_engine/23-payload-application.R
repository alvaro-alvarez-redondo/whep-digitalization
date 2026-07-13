# script: post-processing rule engine — payload application
# description: prepare_rule_payload_execution_plan + apply_rule_payload, the
# per-rule-file orchestration that dispatches footnote rules (see
# 23-footnote-rules.R) and conditional rule groups (see 23-conditional-group.R).

#' @title Prepare rule payload execution plan
#' @description Splits canonical rules into footnote and standard groups and
#' builds a conditional rule dictionary for deterministic application order.
#' @param canonical_rules Canonical rules table.
#' @param stage_name Character scalar stage label.
#' @return Named list with `footnote_rules`, `grouped_dictionary`,
#'   `group_source_columns`, and `stage_name`.
#' @importFrom checkmate assert_data_frame
prepare_rule_payload_execution_plan <- function(canonical_rules, stage_name) {
  checkmate::assert_data_frame(canonical_rules, min.rows = 0)
  validated_stage_name <- validate_postpro_stage_name(stage_name)
  rules_dt <- data.table::as.data.table(canonical_rules)
  footnote_mask <- rules_dt$column_source == "footnotes"
  footnote_rules <- rules_dt[footnote_mask]
  standard_rules <- rules_dt[!footnote_mask]
  grouped_dictionary <- if (nrow(standard_rules) > 0L) {
    build_conditional_rule_dictionary(standard_rules, validated_stage_name)
  } else {
    list()
  }
  group_source_columns <- vapply(
    grouped_dictionary,
    function(g) g$column_source[[1]],
    character(1)
  )
  list(
    footnote_rules = footnote_rules,
    grouped_dictionary = grouped_dictionary,
    group_source_columns = group_source_columns,
    stage_name = validated_stage_name
  )
}

apply_rule_payload <- function(
  dataset_dt,
  canonical_rules,
  stage_name,
  dataset_name,
  rule_file_id,
  execution_timestamp_utc,
  apply_match_normalization = TRUE,
  prepared_payload = NULL,
  trigger_columns = NULL
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
      changed_value_count = 0L,
      changed_columns = character(0)
    ))
  }

  if (is.null(prepared_payload)) {
    prepared_payload <- prepare_rule_payload_execution_plan(
      canonical_rules = canonical_rules,
      stage_name = validated_stage_name
    )
  }
  footnote_rules <- prepared_payload$footnote_rules
  grouped_dictionary <- prepared_payload$grouped_dictionary
  group_source_columns <- prepared_payload$group_source_columns

  audit_tables <- list()
  overwrite_tables <- list()
  changed_value_count <- 0L
  changed_columns <- character(0)
  current_data <- dataset_dt

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
    if (fn_result$changed_value_count > 0L) {
      changed_columns <- union(changed_columns, "footnotes")
    }
    if (nrow(fn_result$overwrite_events) > 0L) {
      overwrite_tables[[length(overwrite_tables) + 1L]] <-
        fn_result$overwrite_events
    }
  }

  if (length(grouped_dictionary) > 0L) {
    for (group_index in seq_len(length(grouped_dictionary))) {
      if (!is.null(trigger_columns) &&
          !(group_source_columns[[group_index]] %in% trigger_columns)) {
        next
      }

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
      if (group_result$changed_value_count > 0L) {
        target_col <- grouped_dictionary[[group_index]]$column_target[[1]]
        changed_columns <- union(changed_columns, target_col)
      }
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
    changed_value_count = as.integer(changed_value_count),
    changed_columns = changed_columns
  ))
}
