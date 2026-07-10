#' Apply target column updates with strategy dispatch
#' Applies conditional and unconditional target updates for one target column
#' using the configured strategy (`last_rule_wins` or `concatenate`).
#' @param dataset_dt `data.table` mutated by reference.
#' @param target_updates `data.frame`/`data.table` containing row and value
#'   updates.
#' @param target_column Character scalar target column to update.
#' @param row_id_column Character scalar row-id column in `target_updates`.
#' @param value_column Character scalar update value column in `target_updates`.
#' @param condition_column Character scalar optional target condition column.
#' @param order_columns Character vector columns used to deterministically order
#'   updates before strategy reduction.
#' @param apply_condition_match Logical scalar enabling condition matching.
#' @param dataset_name Character scalar dataset identifier.
#' @param execution_stage Character scalar execution stage label.
#' @param rule_file_identifier Character scalar rule file identifier.
#' @param source_column Character scalar source column name.
#' @return Named list with `applied` (logical), `overwrite_events`
#'   (`data.table`), and `changed_value_count` (integer).
#' @examples
#' \dontrun{
#' apply_target_updates_with_strategy(dataset_dt, updates, "unit", dataset_name = "whep", execution_stage = "clean", rule_file_identifier = "rules.xlsx", source_column = "commodity")
#' }
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

      # The wildcard token lives at `constants$postpro$rule_match_wildcard_token`,
      # a sibling of `target_update_strategies` — not inside `strategy_config`.
      # Reading it from `strategy_config` yielded NULL, so this guard never fired.
      wildcard_token <- get_pipeline_constants()$postpro$rule_match_wildcard_token
      is_wildcard_condition <- !is.na(conditioned_updates[[condition_column]]) &
        trimws(as.character(conditioned_updates[[condition_column]])) ==
          wildcard_token

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
      anyDuplicated(updates_dt$row_id_internal) == 0L

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

    # `last_rule_wins` only needs the last candidate per row and the candidate
    # count; the distinct-candidate count and the candidate paste are required
    # solely to emit overwrite events, which exist only for rows that received
    # more than one candidate. Keeping the all-rows collapse to last-value + .N
    # avoids a per-group uniqueN()/paste() over the single-candidate majority;
    # both are computed over the (small) multi-candidate subset alone.
    updates_collapsed <- updates_dt[,
      .(
        update_value = update_value[.N],
        candidate_count = .N
      ),
      by = .(row_id_internal)
    ]

    multi_candidate_ids <- updates_collapsed[
      candidate_count > 1L,
      row_id_internal
    ]

    overwrite_events <- if (length(multi_candidate_ids) > 0L) {
      conflict_summary <- updates_dt[
        row_id_internal %in% multi_candidate_ids,
        .(
          candidate_count = .N,
          unique_candidate_count = data.table::uniqueN(update_value),
          selected_value = update_value[.N],
          candidate_values = paste(update_value, collapse = "; ")
        ),
        by = .(row_id_internal)
      ][unique_candidate_count > 1L]

      if (nrow(conflict_summary) > 0L) {
        conflict_summary[, .(
          dataset_name = dataset_name,
          execution_stage = execution_stage,
          rule_file_identifier = rule_file_identifier,
          column_source = source_column,
          column_target = target_column,
          row_id = as.integer(row_id_internal),
          candidate_count = as.integer(candidate_count),
          unique_candidate_count = as.integer(unique_candidate_count),
          selected_value = as.character(selected_value),
          candidate_values = as.character(candidate_values)
        )]
      } else {
        empty_events
      }
    } else {
      empty_events
    }

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
