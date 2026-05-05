# script: clean and harmonize stage functions
# description: load stage-specific rule files and execute vectorized
# conditional transformations via a shared post-processing engine while
# preserving independent stage entry points.

if (!exists("get_pipeline_constants", mode = "function", inherits = TRUE)) {
  source(
    here::here("r", "0-general_pipeline", "01-setup", "01-constants.R"),
    echo = FALSE
  )
  source(
    here::here("r", "0-general_pipeline", "01-setup", "01-config.R"),
    echo = FALSE
  )
  source(
    here::here("r", "0-general_pipeline", "01-setup", "01-directories.R"),
    echo = FALSE
  )
}

# In-memory cache of schema-validation dependency signatures.
.schema_validation_signature_cache <- new.env(parent = emptyenv())

#' @title Load cleaning rule payloads
#' @description Discovers cleaning rule files and returns deterministic payloads.
#' @param config Named configuration list.
#' @return List of payloads with `rule_file_id` and `raw_rules`.
#' @importFrom checkmate assert_list
load_cleaning_rule_payloads <- function(config) {
  checkmate::assert_list(config, min.len = 1)

  return(load_stage_rule_payloads(config = config, stage_name = "clean"))
}

#' @title Load harmonize rule payloads
#' @description Discovers harmonize rule files and returns deterministic payloads.
#' @param config Named configuration list.
#' @return List of payloads with `rule_file_id` and `raw_rules`.
#' @importFrom checkmate assert_list
load_harmonize_rule_payloads <- function(config) {
  checkmate::assert_list(config, min.len = 1)

  return(load_stage_rule_payloads(config = config, stage_name = "harmonize"))
}

#' @title Canonicalize semicolon-delimited cells
#' @description Deduplicates and alphabetically sorts semicolon-delimited tokens
#' within each non-missing cell, then reconstructs deterministic cell strings.
#' @param values Atomic vector of cell values.
#' @param delimiter Character scalar output delimiter.
#' @return Character vector with canonicalized values.
canonicalize_semicolon_delimited_cells <- function(
  values,
  delimiter = get_pipeline_constants()$postpro$target_update_strategies$concatenate_delimiter
) {
  checkmate::assert_atomic(values, any.missing = TRUE)
  checkmate::assert_string(delimiter, min.chars = 1)

  values_chr <- as.character(values)
  values_chr[is.na(values_chr) | trimws(values_chr) == ""] <- NA_character_

  non_missing_idx <- which(!is.na(values_chr))
  if (length(non_missing_idx) == 0L) {
    return(values_chr)
  }

  values_chr[non_missing_idx] <- vapply(
    values_chr[non_missing_idx],
    FUN.VALUE = character(1),
    FUN = function(single_value) {
      split_tokens <- strsplit(single_value, ";", fixed = TRUE)[[1]]
      split_tokens <- trimws(split_tokens)
      split_tokens <- split_tokens[nzchar(split_tokens)]

      if (length(split_tokens) == 0L) {
        return(NA_character_)
      }

      unique_tokens <- split_tokens[!duplicated(split_tokens)]
      sorted_tokens <- sort(unique_tokens, method = "radix")
      paste(sorted_tokens, collapse = delimiter)
    }
  )

  return(values_chr)
}

#' @title Canonicalize post-loop concatenated annotation columns
#' @description Applies per-cell semicolon token canonicalization to notes and
#' footnotes after stage loops complete, preserving global loop performance.
#' @param dataset_dt Data table mutated by reference.
#' @return Invisible logical scalar indicating whether any column was touched.
canonicalize_post_loop_annotation_columns <- function(dataset_dt) {
  checkmate::assert_data_table(dataset_dt)

  annotation_columns <- intersect(c("notes", "footnotes"), names(dataset_dt))
  if (length(annotation_columns) == 0L) {
    return(invisible(FALSE))
  }

  delimiter <- get_pipeline_constants()$postpro$target_update_strategies$concatenate_delimiter

  for (column_name in annotation_columns) {
    data.table::set(
      dataset_dt,
      j = column_name,
      value = canonicalize_semicolon_delimited_cells(
        values = dataset_dt[[column_name]],
        delimiter = delimiter
      )
    )
  }

  return(invisible(TRUE))
}

#' @title Drop empty footnotes column after stage loops
#' @description Removes `footnotes` when every value is missing so the stage
#' can keep the column available during rule execution but omit it from the
#' finalized output when it carries no information.
#' @param dataset_dt Data table mutated by reference.
#' @return Invisible logical scalar indicating whether the column was removed.
drop_empty_footnotes_column <- function(dataset_dt) {
  checkmate::assert_data_table(dataset_dt)

  if (!("footnotes" %in% names(dataset_dt))) {
    return(invisible(FALSE))
  }

  if (all(is.na(dataset_dt[["footnotes"]]))) {
    dataset_dt[, footnotes := NULL]
    return(invisible(TRUE))
  }

  return(invisible(FALSE))
}

#' @title Resolve stage multi-pass controls
#' @description Resolves and validates stage-specific multi-pass controls,
#' applying configuration overrides over centralized defaults.
#' @param config Named configuration list.
#' @param stage_name Character scalar stage name.
#' @return Named list with enabled flag, max passes, cycle policy, and
#' diagnostics verbosity.
#' @importFrom checkmate assert_list assert_string assert_logical assert_integer
#'  assert_character
