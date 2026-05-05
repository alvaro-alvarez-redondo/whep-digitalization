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

#' @title Match rule target conditions against dataset values
#' @description Matches rule target-condition values against current dataset
#' target values. For tokenized columns, semicolon-delimited current values are
#' matched by token membership while preserving exact full-string matching.
#' Wildcards for tokenized columns are explicit and controlled by
#' `get_pipeline_constants()$postpro$rule_match_wildcard_token`.
#' @param current_values Atomic vector of current dataset target values.
#' @param condition_values Atomic vector of rule target-condition values.
#' @param tokenized_target Logical scalar enabling tokenized matching.
#' @param wildcard_token Character scalar explicit wildcard token.
#' @return Logical vector of match decisions.
match_rule_target_condition_values <- function(
  current_values,
  condition_values,
  tokenized_target = FALSE,
  apply_match_normalization = TRUE,
  wildcard_token = get_pipeline_constants()$postpro$rule_match_wildcard_token
) {
  checkmate::assert_atomic(current_values, any.missing = TRUE)
  checkmate::assert_atomic(condition_values, any.missing = TRUE)
  checkmate::assert_flag(tokenized_target)
  checkmate::assert_flag(apply_match_normalization)
  checkmate::assert_string(wildcard_token, min.chars = 1)

  if (length(current_values) != length(condition_values)) {
    cli::cli_abort(
      "current and condition values must have equal length for condition matching"
    )
  }

  if (length(condition_values) == 0L) {
    return(logical(0))
  }

  condition_is_na <- is.na(condition_values)

  if (!isTRUE(tokenized_target)) {
    current_keys <- encode_rule_match_key(
      current_values,
      apply_normalization = apply_match_normalization
    )
    condition_keys <- encode_rule_match_key(
      condition_values,
      apply_normalization = apply_match_normalization
    )

    return(current_keys == condition_keys)
  }

  match_mask <- logical(length(condition_values))
  condition_chr <- as.character(condition_values)
  condition_is_wildcard <-
    !condition_is_na & trimws(condition_chr) == wildcard_token
  match_mask[condition_is_na] <- is.na(current_values[condition_is_na])
  match_mask[condition_is_wildcard] <- TRUE

  non_na_idx <- which(!condition_is_na & !condition_is_wildcard)
  if (length(non_na_idx) == 0L) {
    return(match_mask)
  }

  current_values_chr <- as.character(current_values[non_na_idx])
  condition_keys <- encode_rule_match_key(
    condition_values[non_na_idx],
    apply_normalization = apply_match_normalization
  )

  unique_current_values <- unique(current_values_chr[
    !is.na(current_values_chr)
  ])

  token_lookup <- setNames(
    lapply(unique_current_values, function(value_chr) {
      split_tokens <- strsplit(value_chr, ";", fixed = TRUE)[[1]]
      split_tokens <- trimws(split_tokens)
      split_tokens <- split_tokens[nzchar(split_tokens)]

      token_keys <- character(0)
      if (length(split_tokens) > 0L) {
        token_keys <- encode_rule_match_key(
          split_tokens,
          apply_normalization = apply_match_normalization
        )
      }

      full_key <- encode_rule_match_key(
        value_chr,
        apply_normalization = apply_match_normalization
      )

      return(unique(c(token_keys, full_key)))
    }),
    unique_current_values
  )

  for (idx_pos in seq_along(non_na_idx)) {
    out_idx <- non_na_idx[[idx_pos]]
    row_value_chr <- current_values_chr[[idx_pos]]

    if (is.na(row_value_chr)) {
      match_mask[[out_idx]] <- FALSE
      next
    }

    row_tokens <- token_lookup[[row_value_chr]]
    match_mask[[out_idx]] <- condition_keys[[idx_pos]] %in% row_tokens
  }

  return(match_mask)
}

#' @title Concatenate existing and incoming target values
#' @description Appends incoming values to existing values using a deterministic
#' delimiter while preserving missing-value semantics.
#' @param existing_values Atomic vector of current dataset values.
#' @param incoming_values Atomic vector of incoming update values.
#' @param delimiter Character scalar concatenation delimiter.
#' @return Character vector merged values.
concatenate_existing_and_incoming_values <- function(
  existing_values,
  incoming_values,
  delimiter
) {
  checkmate::assert_atomic(existing_values, any.missing = TRUE)
  checkmate::assert_atomic(incoming_values, any.missing = TRUE)
  checkmate::assert_string(delimiter, min.chars = 1)

  if (length(existing_values) != length(incoming_values)) {
    cli::cli_abort(
      "existing and incoming values must have equal length for concatenation"
    )
  }

  existing_values_norm <- as.character(existing_values)
  incoming_values_norm <- as.character(incoming_values)

  existing_values_norm[
    is.na(existing_values_norm) | trimws(existing_values_norm) == ""
  ] <- NA_character_
  incoming_values_norm[
    is.na(incoming_values_norm) | trimws(incoming_values_norm) == ""
  ] <- NA_character_

  split_deduplicate_tokens <- function(values_chr) {
    lapply(values_chr, function(single_value) {
      if (is.na(single_value)) {
        return(character(0))
      }

      split_tokens <- strsplit(single_value, ";", fixed = TRUE)[[1]]
      split_tokens <- trimws(split_tokens)
      split_tokens <- split_tokens[nzchar(split_tokens)]

      if (length(split_tokens) == 0L) {
        return(character(0))
      }

      dedup_mask <- !duplicated(split_tokens)
      return(split_tokens[dedup_mask])
    })
  }

  merged_values <- incoming_values_norm
  existing_only_mask <- !is.na(existing_values_norm) &
    is.na(incoming_values_norm)
  both_present_mask <- !is.na(existing_values_norm) &
    !is.na(incoming_values_norm)

  if (any(existing_only_mask)) {
    merged_values[existing_only_mask] <- existing_values_norm[
      existing_only_mask
    ]
  }

  if (any(both_present_mask)) {
    existing_tokens <- split_deduplicate_tokens(existing_values_norm[
      both_present_mask
    ])
    incoming_tokens <- split_deduplicate_tokens(incoming_values_norm[
      both_present_mask
    ])

    merged_values[both_present_mask] <- vapply(
      seq_along(existing_tokens),
      FUN.VALUE = character(1),
      FUN = function(idx) {
        merged_tokens <- c(existing_tokens[[idx]], incoming_tokens[[idx]])
        merged_tokens <- merged_tokens[!duplicated(merged_tokens)]
        if (length(merged_tokens) == 0L) {
          return(NA_character_)
        }
        paste(merged_tokens, collapse = delimiter)
      }
    )
  }

  return(merged_values)
}

#' @title Count element-wise value changes
#' @description Counts deterministic value changes between two same-length
#' vectors while preserving missing-value semantics.
#' @param before_values Atomic vector of values before mutation.
#' @param after_values Atomic vector of values after mutation.
#' @return Integer scalar count of changed elements.
count_elementwise_value_changes <- function(before_values, after_values) {
  checkmate::assert_atomic(before_values, any.missing = TRUE)
  checkmate::assert_atomic(after_values, any.missing = TRUE)

  if (length(before_values) != length(after_values)) {
    cli::cli_abort("before and after vectors must have equal length")
  }

  if (length(before_values) == 0L) {
    return(0L)
  }

  before_na <- is.na(before_values)
  after_na <- is.na(after_values)

  value_changed <- before_na != after_na
  comparable_mask <- !before_na & !after_na

  if (any(comparable_mask)) {
    value_changed[comparable_mask] <-
      as.character(before_values[comparable_mask]) !=
        as.character(after_values[comparable_mask])
  }

  return(as.integer(sum(value_changed)))
}

#' @title Apply target updates with strategy dispatch
#' @description Applies conditional and unconditional target updates for one
#' target column using a configured strategy (`last_rule_wins` or
#' `concatenate`).
#' @param dataset_dt Data table mutated by reference.
#' @param target_updates Data frame/data.table containing row and value updates.
#' @param target_column Character scalar target column to update.
#' @param row_id_column Character scalar row-id column in `target_updates`.
#' @param value_column Character scalar update value column in `target_updates`.
#' @param condition_column Character scalar optional target condition column.
#' @param order_columns Character vector columns used to deterministically order
#' updates before strategy reduction.
#' @return Invisible logical scalar indicating whether any update was applied.
