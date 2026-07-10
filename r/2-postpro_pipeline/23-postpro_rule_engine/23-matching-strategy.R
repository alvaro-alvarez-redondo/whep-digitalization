#' Encode target rule values with explicit NA placeholder
#' Converts missing and empty-string values to an internal NA placeholder token
#' to support deterministic rule matching.
#' @param values Atomic vector of values to encode.
#' @param na_placeholder Character scalar internal missing token.
#' @return Character vector with placeholder-encoded values.
#' @examples
#' encode_target_rule_value(c("a", NA, ""))
encode_target_rule_value <- function(
  values,
  na_placeholder = get_pipeline_constants()$na_placeholder
) {
  checkmate::assert_atomic(values, min.len = 0, any.missing = TRUE)
  checkmate::assert_string(na_placeholder, min.chars = 1)

  if (length(values) == 0L) {
    return(character(0))
  }

  encoded_values <- as.character(values)
  encoded_values[trimws(encoded_values) == ""] <- na_placeholder
  encoded_values[is.na(encoded_values)] <- na_placeholder

  return(encoded_values)
}

#' @title Decode internal placeholder back to `NA_character_`
#' @description Reverts encoded missing target values to canonical
#' `NA_character_` representation before rule application.
#' @param values Character vector values to decode.
#' @param na_placeholder Character scalar internal missing token.
#' @return Character vector with placeholder decoded to `NA_character_`.
#' @importFrom checkmate assert_character assert_string
decode_target_rule_value <- function(
  values,
  na_placeholder = get_pipeline_constants()$na_placeholder
) {
  checkmate::assert_character(values, any.missing = TRUE)
  checkmate::assert_string(na_placeholder, min.chars = 1)

  decoded_values <- values
  decoded_values[decoded_values == na_placeholder] <- NA_character_

  return(decoded_values)
}

#' @title Build deterministic matching keys with explicit NA handling
#' @description Normalizes values to comparable string keys and maps missing
#' values to an explicit internal token to guarantee deterministic NA matching
#' behavior during join operations.
#' @param values Atomic vector values to encode.
#' @param na_key Character scalar NA token used for matching keys.
#' @return Character vector key.
#' @importFrom checkmate assert_atomic assert_string
encode_rule_match_key <- function(
  values,
  na_key = get_pipeline_constants()$na_match_key,
  apply_normalization = TRUE
) {
  checkmate::assert_atomic(values, min.len = 0, any.missing = TRUE)
  checkmate::assert_string(na_key, min.chars = 1)
  checkmate::assert_flag(apply_normalization)

  if (length(values) == 0L) {
    return(character(0))
  }

  encoded_key <- as.character(values)
  if (isTRUE(apply_normalization)) {
    encoded_key <- normalize_string(values)
  }
  encoded_key[is.na(encoded_key)] <- na_key

  return(encoded_key)
}

#' @title Resolve rule match normalization settings
#' @description Returns centralized settings controlling when match-key
#' normalization is applied.
#' @return Named list with `apply_once_before_stage`, `apply_each_pass`, and
#' `excluded_columns`.
resolve_rule_match_normalization_settings <- function() {
  settings <- get_pipeline_constants()$postpro$rule_match_normalization
  checkmate::assert_list(settings, min.len = 1)

  apply_once_before_stage <- isTRUE(settings$apply_once_before_stage)
  apply_each_pass <- isTRUE(settings$apply_each_pass)
  excluded_columns <- settings$excluded_columns

  if (is.null(excluded_columns)) {
    excluded_columns <- character(0)
  }
  checkmate::assert_character(excluded_columns, any.missing = FALSE)

  return(list(
    apply_once_before_stage = apply_once_before_stage,
    apply_each_pass = apply_each_pass,
    excluded_columns = excluded_columns
  ))
}

#' @title Empty last-rule-wins overwrite events table
#' @description Returns a standardized empty table used to collect overwrite
#' diagnostics triggered by the `last_rule_wins` strategy.
#' @return Empty `data.table` with overwrite event columns.
empty_last_rule_wins_overwrite_events_dt <- function() {
  return(data.table::data.table(
    dataset_name = character(),
    execution_stage = character(),
    rule_file_identifier = character(),
    column_source = character(),
    column_target = character(),
    row_id = integer(),
    candidate_count = integer(),
    unique_candidate_count = integer(),
    selected_value = character(),
    candidate_values = character()
  ))
}

#' @title Get target-update strategy configuration
#' @description Validates and returns centralized target-update strategies used
#' by post-processing rule application.
#' @return Named list with default strategy, supported strategies,
#' concatenate delimiter, and optional per-column overrides.
get_target_update_strategy_config <- function() {
  strategy_config <- get_pipeline_constants()$postpro$target_update_strategies

  if (is.null(strategy_config)) {
    cli::cli_abort(c(
      "missing target-update strategy configuration in pipeline constants.",
      "x" = "expected get_pipeline_constants()$postpro$target_update_strategies"
    ))
  }

  checkmate::assert_list(strategy_config, min.len = 1)
  checkmate::assert_string(strategy_config$default, min.chars = 1)
  checkmate::assert_character(
    strategy_config$supported,
    min.len = 1,
    any.missing = FALSE,
    unique = TRUE
  )
  checkmate::assert_string(
    strategy_config$concatenate_delimiter,
    min.chars = 1
  )

  if (!(strategy_config$default %in% strategy_config$supported)) {
    cli::cli_abort(c(
      "invalid target-update strategy configuration.",
      "x" = "default strategy is not listed in supported strategies"
    ))
  }

  by_column <- strategy_config$by_column
  if (is.null(by_column)) {
    by_column <- character(0)
  }

  if (is.list(by_column)) {
    by_column <- unlist(by_column, recursive = FALSE, use.names = TRUE)
  }

  checkmate::assert_character(by_column, any.missing = FALSE)

  if (
    length(by_column) > 0L &&
      (is.null(names(by_column)) || any(!nzchar(trimws(names(by_column)))))
  ) {
    cli::cli_abort(
      "target-update column overrides must be a named character vector"
    )
  }

  strategy_config$by_column <- by_column

  return(strategy_config)
}

#' @title Resolve target-update strategy for one column
#' @description Returns the configured strategy for a target column,
#' falling back to the centralized default strategy.
#' @param target_column Character scalar target column.
#' @param strategy_config Named strategy configuration list.
#' @return Character scalar strategy name.
resolve_target_update_strategy <- function(
  target_column,
  strategy_config = get_target_update_strategy_config()
) {
  checkmate::assert_string(target_column, min.chars = 1)
  checkmate::assert_list(strategy_config, min.len = 1)

  resolved_strategy <- strategy_config$default

  if (
    length(strategy_config$by_column) > 0L &&
      target_column %in% names(strategy_config$by_column)
  ) {
    resolved_strategy <- unname(strategy_config$by_column[[target_column]])
  }

  if (!(resolved_strategy %in% strategy_config$supported)) {
    cli::cli_abort(c(
      "unsupported target-update strategy configured.",
      "x" = paste0(
        "column: ",
        target_column,
        "; strategy: ",
        resolved_strategy,
        "; supported: ",
        paste(strategy_config$supported, collapse = ", ")
      )
    ))
  }

  return(resolved_strategy)
}

#' @title Resolve unique-row fast-path toggle for last-rule-wins
#' @description Returns whether the unique-row direct-update fast path is
#' enabled for `last_rule_wins` target updates.
#' @return Logical scalar fast-path toggle.
resolve_last_rule_wins_unique_row_fast_path_enabled <- function() {
  fast_path_config <- get_pipeline_constants()$postpro$target_update_fast_path

  if (!is.list(fast_path_config)) {
    return(FALSE)
  }

  return(isTRUE(fast_path_config$last_rule_wins_unique_row_id))
}

#' @title Resolve tokenized target-condition columns
#' @description Returns columns whose target-condition matching should treat
#' semicolon-delimited values as token sets. This is enabled for concatenate
#' strategy columns and always for `footnotes`.
#' @param strategy_config Named strategy configuration list.
#' @return Character vector of tokenized target-condition columns.
resolve_tokenized_target_condition_columns <- function(
  strategy_config = get_target_update_strategy_config()
) {
  checkmate::assert_list(strategy_config, min.len = 1)

  by_column <- strategy_config$by_column
  if (is.null(by_column)) {
    by_column <- character(0)
  }

  if (is.list(by_column)) {
    by_column <- unlist(by_column, recursive = FALSE, use.names = TRUE)
  }

  checkmate::assert_character(by_column, any.missing = FALSE)

  concatenate_columns <- character(0)
  if (length(by_column) > 0L && !is.null(names(by_column))) {
    concatenate_columns <- names(by_column)[by_column == "concatenate"]
  }

  return(sort(unique(c(concatenate_columns, "footnotes"))))
}
