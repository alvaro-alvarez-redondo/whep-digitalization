run_rule_stage_layer_batch <- function(
  dataset_dt,
  config,
  stage_name,
  dataset_name = get_pipeline_constants()$dataset_default_name
) {
  checkmate::assert_data_frame(dataset_dt, min.rows = 0)
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(stage_name, min.chars = 1)
  checkmate::assert_string(dataset_name, min.chars = 1)

  validated_stage_name <- validate_postpro_stage_name(stage_name)

  payload_bundle <- get_cached_stage_payload_bundle(
    config = config,
    stage_name = validated_stage_name
  )

  canonical_payloads <- payload_bundle$canonical_payloads
  if (!is.list(canonical_payloads)) {
    canonical_payloads <- list()
  }

  rule_match_normalization_settings <- resolve_rule_match_normalization_settings()

  payload_cache_key <- payload_bundle$cache_key
  if (is.null(payload_cache_key)) {
    payload_cache_key <- paste0(
      validated_stage_name,
      "::<no_payload_cache_key>"
    )
  }

  working_data <- data.table::copy(data.table::as.data.table(dataset_dt))

  schema_validation_cache_settings <- resolve_schema_validation_cache_settings(
    config = config
  )

  if (length(canonical_payloads) > 0L) {
    for (payload in canonical_payloads) {
      working_data <- ensure_rule_referenced_columns(
        dataset_dt = working_data,
        rules_dt = payload$canonical_rules
      )

      dependency_signature <- build_schema_validation_dependency_signature(
        dataset_dt = working_data,
        canonical_rules = payload$canonical_rules,
        stage_name = validated_stage_name,
        rule_file_id = payload$rule_file_id,
        payload_cache_key = payload_cache_key
      )

      if (
        !is_schema_validation_signature_cached(
          dependency_signature = dependency_signature,
          cache_settings = schema_validation_cache_settings
        )
      ) {
        validate_canonical_rules(
          rules_dt = payload$canonical_rules,
          dataset_dt = working_data,
          rule_file_id = payload$rule_file_id,
          stage_name = validated_stage_name
        )

        memoize_schema_validation_signature(
          dependency_signature = dependency_signature,
          cache_settings = schema_validation_cache_settings
        )
      }
    }
  }

  multi_pass_controls <- resolve_stage_multi_pass_controls(
    config = config,
    stage_name = validated_stage_name
  )

  max_stage_passes <- if (isTRUE(multi_pass_controls$enabled)) {
    as.integer(multi_pass_controls$max_passes)
  } else {
    1L
  }

  execution_timestamp_utc <- format(
    Sys.time(),
    get_pipeline_constants()$timestamp_format_utc,
    tz = "UTC"
  )

  all_pass_audit_tables <- list()
  all_pass_overwrite_tables <- list()
  per_pass_diagnostics <- list()

  converged <- FALSE
  cycle_detected <- FALSE
  max_passes_reached_before_convergence <- FALSE
  cycle_message <- NULL
  max_passes_message <- NULL
  multi_pass_enabled <- isTRUE(multi_pass_controls$enabled)
  stage_stop_reason <- if (isTRUE(multi_pass_enabled)) {
    "converged_zero_change"
  } else {
    "single_pass_completed"
  }

  state_signatures <- list()
  state_pass_indexes <- integer(0)

  if (isTRUE(multi_pass_enabled)) {
    state_signatures <- list(serialize_stage_state_signature(working_data))
    state_pass_indexes <- c(0L)
  }

  for (pass_index in seq_len(max_stage_passes)) {
    pass_state <- list(
      data = working_data,
      audit_tables = list(),
      overwrite_tables = list(),
      changed_value_count = 0L
    )

    apply_match_normalization_for_pass <-
      isTRUE(rule_match_normalization_settings$apply_each_pass) ||
      (isTRUE(rule_match_normalization_settings$apply_once_before_stage) &&
        pass_index == 1L)

    if (length(canonical_payloads) > 0L) {
      pass_state <- purrr::reduce(
        .x = canonical_payloads,
        .init = pass_state,
        .f = function(state, payload) {
          if (nrow(payload$canonical_rules) == 0L) {
            return(state)
          }

          payload_result <- apply_rule_payload(
            dataset_dt = state$data,
            canonical_rules = payload$canonical_rules,
            stage_name = validated_stage_name,
            dataset_name = dataset_name,
            rule_file_id = payload$rule_file_id,
            execution_timestamp_utc = execution_timestamp_utc,
            apply_match_normalization = apply_match_normalization_for_pass
          )

          state$data <- payload_result$data
          state$audit_tables[[
            length(state$audit_tables) + 1L
          ]] <- payload_result$audit
          if (nrow(payload_result$overwrite_events) > 0L) {
            state$overwrite_tables[[
              length(state$overwrite_tables) + 1L
            ]] <- payload_result$overwrite_events
          }

          state$changed_value_count <-
            state$changed_value_count + payload_result$changed_value_count

          return(state)
        }
      )
    }

    pass_audit <- data.table::rbindlist(
      pass_state$audit_tables,
      use.names = TRUE,
      fill = TRUE
    )
    pass_audit[, loop := as.integer(pass_index)]

    pass_overwrite_events <- if (length(pass_state$overwrite_tables) > 0L) {
      data.table::rbindlist(
        pass_state$overwrite_tables,
        use.names = TRUE,
        fill = TRUE
      )
    } else {
      empty_last_rule_wins_overwrite_events_dt()
    }

    pass_matched_count <- if (nrow(pass_audit) == 0L) {
      0L
    } else {
      as.integer(sum(pass_audit$affected_rows))
    }

    pass_stop_reason <- "continued"
    current_signature <- NULL
    repeated_state_pass <- NA_integer_

    if (isTRUE(multi_pass_enabled)) {
      if (pass_state$changed_value_count == 0L) {
        # Zero changed values means pass output equals pass input.
        repeated_state_pass <- as.integer(pass_index - 1L)
        converged <- TRUE
        pass_stop_reason <- "converged_zero_change"
        stage_stop_reason <- pass_stop_reason
      } else {
        current_signature <- serialize_stage_state_signature(pass_state$data)
        repeated_state_pass <- find_repeated_stage_state_pass(
          state_signatures = state_signatures,
          state_pass_indexes = state_pass_indexes,
          candidate_signature = current_signature
        )

        if (!is.na(repeated_state_pass)) {
          if (repeated_state_pass == (pass_index - 1L)) {
            converged <- TRUE
            pass_stop_reason <- "converged_zero_change"
            stage_stop_reason <- pass_stop_reason
          } else {
            cycle_detected <- TRUE
            pass_stop_reason <- "cycle_detected"
            stage_stop_reason <- pass_stop_reason
            cycle_message <- paste0(
              "[",
              validated_stage_name,
              " stage] cycle detected at pass ",
              pass_index,
              " (repeats pass ",
              repeated_state_pass,
              ")."
            )

            if (identical(multi_pass_controls$cycle_policy, "abort")) {
              cli::cli_abort(c(
                "Post-processing multi-pass cycle detected.",
                "x" = cycle_message
              ))
            }

            cli::cli_warn(c(
              "Post-processing multi-pass cycle detected; stopping stage execution.",
              "!" = cycle_message
            ))
          }
        } else {
          state_signatures[[length(state_signatures) + 1L]] <- current_signature
          state_pass_indexes <- c(state_pass_indexes, as.integer(pass_index))
        }
      }
    }

    is_final_allowed_pass <- pass_index >= max_stage_passes
    should_warn_on_max_pass <-
      isTRUE(multi_pass_enabled) &&
      pass_stop_reason == "continued" &&
      is_final_allowed_pass

    should_stop_single_pass <-
      !isTRUE(multi_pass_enabled) &&
      pass_stop_reason == "continued" &&
      is_final_allowed_pass

    if (should_warn_on_max_pass) {
      max_passes_reached_before_convergence <- TRUE
      pass_stop_reason <- "max_passes_reached"
      stage_stop_reason <- pass_stop_reason
      max_passes_message <- paste0(
        "[",
        validated_stage_name,
        " stage] reached max_passes=",
        max_stage_passes,
        " before convergence."
      )

      cli::cli_warn(c(
        "Post-processing multi-pass max-pass limit reached.",
        "!" = max_passes_message
      ))
    }

    if (should_stop_single_pass) {
      pass_stop_reason <- "single_pass_completed"
      stage_stop_reason <- pass_stop_reason
    }

    per_pass_diagnostics[[length(per_pass_diagnostics) + 1L]] <-
      data.table::data.table(
        pass_index = as.integer(pass_index),
        changed_value_count = as.integer(pass_state$changed_value_count),
        matched_count = as.integer(pass_matched_count),
        audit_rows = as.integer(nrow(pass_audit)),
        overwrite_event_rows = as.integer(nrow(pass_overwrite_events)),
        repeated_state_pass = repeated_state_pass,
        stop_reason = pass_stop_reason
      )

    all_pass_audit_tables[[length(all_pass_audit_tables) + 1L]] <- pass_audit

    if (nrow(pass_overwrite_events) > 0L) {
      all_pass_overwrite_tables[[
        length(all_pass_overwrite_tables) + 1L
      ]] <- pass_overwrite_events
    }

    working_data <- pass_state$data

    if (!identical(pass_stop_reason, "continued")) {
      break
    }
  }

  canonicalize_post_loop_annotation_columns(working_data)
  drop_empty_footnotes_column(working_data)

  stage_audit <- data.table::rbindlist(
    all_pass_audit_tables,
    use.names = TRUE,
    fill = TRUE
  )

  stage_overwrite_events <- if (length(all_pass_overwrite_tables) > 0L) {
    data.table::rbindlist(
      all_pass_overwrite_tables,
      use.names = TRUE,
      fill = TRUE
    )
  } else {
    empty_last_rule_wins_overwrite_events_dt()
  }

  pass_diagnostics_dt <- data.table::rbindlist(
    per_pass_diagnostics,
    use.names = TRUE,
    fill = TRUE
  )

  diagnostics <- build_layer_diagnostics(
    layer_name = validated_stage_name,
    rows_in = nrow(dataset_dt),
    rows_out = nrow(working_data),
    audit_dt = stage_audit
  )

  diagnostics_messages <- diagnostics$messages
  if (is.null(diagnostics_messages)) {
    diagnostics_messages <- character(0)
  }
  diagnostics_messages <- as.character(diagnostics_messages)
  diagnostics_messages <- diagnostics_messages[!is.na(diagnostics_messages)]

  multi_pass_summary <- paste0(
    "[",
    validated_stage_name,
    " stage] multi-pass stop_reason=",
    stage_stop_reason,
    "; passes_executed=",
    nrow(pass_diagnostics_dt),
    "; max_passes=",
    max_stage_passes,
    "; enabled=",
    tolower(as.character(multi_pass_enabled)),
    "."
  )

  diagnostics_messages <- c(diagnostics_messages, multi_pass_summary)
  if (!is.null(cycle_message)) {
    diagnostics_messages <- c(diagnostics_messages, cycle_message)
  }
  if (!is.null(max_passes_message)) {
    diagnostics_messages <- c(diagnostics_messages, max_passes_message)
  }

  diagnostics$messages <- diagnostics_messages
  diagnostics$multi_pass <- list(
    enabled = isTRUE(multi_pass_enabled),
    max_passes = as.integer(max_stage_passes),
    passes_executed = as.integer(nrow(pass_diagnostics_dt)),
    converged = isTRUE(converged),
    cycle_detected = isTRUE(cycle_detected),
    max_passes_reached_before_convergence = isTRUE(
      max_passes_reached_before_convergence
    ),
    cycle_policy = multi_pass_controls$cycle_policy,
    diagnostics_verbosity = multi_pass_controls$diagnostics_verbosity,
    stop_reason = stage_stop_reason
  )

  if (identical(multi_pass_controls$diagnostics_verbosity, "verbose")) {
    diagnostics$multi_pass$pass_diagnostics <- pass_diagnostics_dt
  }

  stage_output_dt <- working_data
  attr(stage_output_dt, "layer_diagnostics") <- diagnostics
  attr(stage_output_dt, "layer_audit") <- stage_audit
  attr(stage_output_dt, "layer_last_rule_wins_overwrites") <-
    stage_overwrite_events
  attr(stage_output_dt, "layer_multi_pass_diagnostics") <- pass_diagnostics_dt

  return(stage_output_dt)
}

#' @title Run cleaning layer batch
#' @description Applies clean-stage conditional rules and returns clean data
#' with diagnostics and audit metadata.
#' @param dataset_dt Input dataset as data.frame/data.table.
#' @param config Named configuration list.
#' @param dataset_name Character scalar dataset identifier.
#' @return clean `data.table` with attributes `layer_diagnostics` and
#' `layer_audit`.
#' @importFrom checkmate assert_data_frame assert_list assert_string
run_cleaning_layer_batch <- function(
  dataset_dt,
  config,
  dataset_name = get_pipeline_constants()$dataset_default_name
) {
  checkmate::assert_data_frame(dataset_dt, min.rows = 0)
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(dataset_name, min.chars = 1)

  return(run_rule_stage_layer_batch(
    dataset_dt = dataset_dt,
    config = config,
    stage_name = "clean",
    dataset_name = dataset_name
  ))
}

#' @title Run harmonize layer batch
#' @description Applies harmonize-stage conditional rules and returns harmonize
#' data with diagnostics and audit metadata.
#' @param dataset_dt Input dataset as data.frame/data.table.
#' @param config Named configuration list.
#' @param dataset_name Character scalar dataset identifier.
#' @return harmonize `data.table` with attributes `layer_diagnostics` and
#' `layer_audit`.
#' @importFrom checkmate assert_data_frame assert_list assert_string
run_harmonize_layer_batch <- function(
  dataset_dt,
  config,
  dataset_name = get_pipeline_constants()$dataset_default_name
) {
  checkmate::assert_data_frame(dataset_dt, min.rows = 0)
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(dataset_name, min.chars = 1)

  return(run_rule_stage_layer_batch(
    dataset_dt = dataset_dt,
    config = config,
    stage_name = "harmonize",
    dataset_name = dataset_name
  ))
}
