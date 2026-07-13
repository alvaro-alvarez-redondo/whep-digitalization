# script: post-processing rule engine — matching & value merge
# description: target-condition matching (match_rule_target_condition_values),
# concatenate-strategy value merge, and element-wise change counting. Split
# from 23-matching-strategy.R (>500-line policy); pure definitions sourced with
# the rest of the 23-postpro_rule_engine stage.

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

  #' Split and Deduplicate Semicolon-Delimited Tokens
  #'
  #' Splits semicolon-delimited strings into trimmed tokens, removes empties,
  #' deduplicates them, and returns a list of character vectors.
  #'
  #' @param values_chr Character vector of semicolon-delimited strings.
  #' @return List of character vectors with deduplicated tokens.
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
