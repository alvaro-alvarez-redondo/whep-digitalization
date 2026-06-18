# header normalization helpers

#' Normalize header names for canonical matching
#' @description Trims whitespace, collapses internal spacing, lowercases to
#' ASCII, removes separator padding around `/` and `-`, and replaces remaining
#' punctuation/space runs with underscores while preserving `/` and `-`.
#' @param header_names Character vector of raw header names.
#' @return Character vector of normalized header keys.
#' @examples
#' normalize_header_names(c(" Country Name ", "Year / Period"))
normalize_header_names <- function(header_names) {
  assert_or_abort(checkmate::check_character(
    header_names,
    any.missing = TRUE
  ))

  constants <- get_pipeline_constants()
  whitespace_pattern <- constants$patterns$header_normalize_whitespace
  separator_pattern <- constants$patterns$header_normalize_separator_spacing
  non_alnum_pattern <- constants$patterns$header_normalize_non_alnum
  underscore_pattern <- constants$patterns$header_normalize_multi_underscore
  trim_underscore_pattern <- constants$patterns$header_normalize_trim_underscore
  fast_path_pattern <- constants$patterns$header_normalize_fast_path
  transliterate_rule <- constants$transforms$latin_ascii_lower
  replacements <- constants$header_normalization

  header_chr <- as.character(header_names)
  non_na_idx <- !is.na(header_chr)

  if (!any(non_na_idx)) {
    return(header_chr)
  }

  header_non_na <- header_chr[non_na_idx]

  fast_path_ok <- all(stringi::stri_detect_regex(
    header_non_na,
    fast_path_pattern
  ))

  if (fast_path_ok) {
    has_multi_underscore <- any(stringi::stri_detect_regex(
      header_non_na,
      underscore_pattern
    ))
    has_trim_underscore <- any(stringi::stri_detect_regex(
      header_non_na,
      trim_underscore_pattern
    ))

    if (!has_multi_underscore && !has_trim_underscore) {
      return(header_chr)
    }
  }

  header_norm <- stringi::stri_trim_both(header_non_na)
  header_norm <- stringi::stri_replace_all_regex(
    header_norm,
    whitespace_pattern,
    replacements$whitespace_replacement
  )
  header_norm <- stringi::stri_replace_all_regex(
    header_norm,
    separator_pattern,
    replacements$separator_replacement
  )
  header_norm <- stringi::stri_trans_general(
    header_norm,
    transliterate_rule
  )
  header_norm <- stringi::stri_replace_all_regex(
    header_norm,
    non_alnum_pattern,
    replacements$non_alnum_replacement
  )
  header_norm <- stringi::stri_replace_all_regex(
    header_norm,
    underscore_pattern,
    replacements$non_alnum_replacement
  )
  header_norm <- stringi::stri_replace_all_regex(
    header_norm,
    trim_underscore_pattern,
    replacements$trim_underscore_replacement
  )

  header_chr[non_na_idx] <- header_norm

  return(header_chr)
}

#' Validate normalized header names
#' @description Detects collisions created by header normalization.
#' @param header_names Character vector of raw header names.
#' @param normalized_header_names Character vector of normalized header names.
#' @param file_path Character scalar path to the workbook being read.
#' @param sheet_name Character scalar worksheet name.
#' @return Character vector with formatted errors (empty when valid).
#' @examples
#' validate_header_normalization(c("A B", "A  B"), c("a_b", "a_b"), "f.xlsx", "Sheet1")
validate_header_normalization <- function(
  header_names,
  normalized_header_names,
  file_path,
  sheet_name
) {
  assert_or_abort(checkmate::check_character(
    header_names,
    any.missing = TRUE
  ))
  assert_or_abort(checkmate::check_character(
    normalized_header_names,
    any.missing = TRUE
  ))
  assert_or_abort(checkmate::check_true(
    length(header_names) == length(normalized_header_names)
  ))
  assert_or_abort(checkmate::check_string(file_path, min.chars = 1))
  assert_or_abort(checkmate::check_string(sheet_name, min.chars = 1))

  valid_mask <- !is.na(normalized_header_names) &
    nzchar(normalized_header_names)
  normalized_valid <- normalized_header_names[valid_mask]

  if (length(normalized_valid) == 0L) {
    return(character(0))
  }

  dup_mask <- duplicated(normalized_valid) |
    duplicated(normalized_valid, fromLast = TRUE)

  if (!any(dup_mask)) {
    return(character(0))
  }

  duplicates <- unique(normalized_valid[dup_mask])

  return(cli::format_error(c(
    "normalized header collision detected in sheet {.val {sheet_name}} for file {.file {fs::path_file(file_path)}}.",
    "x" = paste(duplicates, collapse = ", ")
  )))
}

#' Resolve canonical header renames
#' @description Maps normalized header names to canonical pipeline columns.
#' @param header_names Character vector of raw header names.
#' @param normalized_header_names Character vector of normalized header names.
#' @param canonical_names Character vector of canonical column names.
#' @param alias_map Named character vector mapping alias names to canonical
#'   targets (defaults to constants when `NULL`).
#' @return List with `old` and `new` vectors for `data.table::setnames`.
#' @examples
#' resolve_canonical_header_renames(c(" Continent "), c("continent"), c("continent"))
resolve_canonical_header_renames <- function(
  header_names,
  normalized_header_names,
  canonical_names,
  alias_map = NULL
) {
  assert_or_abort(checkmate::check_character(
    header_names,
    any.missing = TRUE
  ))
  assert_or_abort(checkmate::check_character(
    normalized_header_names,
    any.missing = TRUE
  ))
  assert_or_abort(checkmate::check_true(
    length(header_names) == length(normalized_header_names)
  ))
  assert_or_abort(checkmate::check_character(
    canonical_names,
    any.missing = TRUE
  ))

  if (!is.null(alias_map)) {
    assert_or_abort(checkmate::check_character(alias_map, any.missing = TRUE))
  }

  canonical_names <- unique(canonical_names)
  canonical_names <- canonical_names[
    !is.na(canonical_names) & nzchar(canonical_names)
  ]

  if (length(canonical_names) == 0L) {
    return(list(old = character(0), new = character(0)))
  }

  canonical_norm <- normalize_header_names(canonical_names)
  match_idx <- match(canonical_norm, normalized_header_names)
  has_exact_name <- canonical_names %in% header_names
  match_idx[has_exact_name] <- NA_integer_

  rename_mask <- !is.na(match_idx)
  old_names <- character(0)
  new_names <- character(0)

  if (any(rename_mask)) {
    old_names <- header_names[match_idx[rename_mask]]
    new_names <- canonical_names[rename_mask]
  }

  if (is.null(alias_map)) {
    alias_map <- get_pipeline_constants()$header_normalization$canonical_aliases
  }

  alias_names <- names(alias_map)
  alias_targets <- unname(alias_map)

  if (!is.null(alias_names) && length(alias_names) > 0L) {
    alias_mask <- !is.na(alias_names) & nzchar(alias_names) &
      !is.na(alias_targets) & nzchar(alias_targets)

    alias_names <- alias_names[alias_mask]
    alias_targets <- alias_targets[alias_mask]

    if (length(alias_names) > 0L) {
      alias_keep <- alias_targets %in% canonical_names
      alias_names <- alias_names[alias_keep]
      alias_targets <- alias_targets[alias_keep]
    }

    if (length(alias_names) > 0L) {
      alias_norm <- normalize_header_names(alias_names)
      alias_match_idx <- match(alias_norm, normalized_header_names)

      target_present <- alias_targets %in% c(header_names, new_names)
      alias_match_idx[target_present] <- NA_integer_

      alias_rename_mask <- !is.na(alias_match_idx)
      if (any(alias_rename_mask)) {
        alias_old <- header_names[alias_match_idx[alias_rename_mask]]
        alias_new <- alias_targets[alias_rename_mask]

        alias_keep <- !(alias_old %in% old_names)
        if (any(alias_keep)) {
          old_names <- c(old_names, alias_old[alias_keep])
          new_names <- c(new_names, alias_new[alias_keep])
        }
      }
    }
  }

  if (length(old_names) == 0L) {
    return(list(old = character(0), new = character(0)))
  }

  unchanged_mask <- old_names == new_names
  if (any(unchanged_mask)) {
    old_names <- old_names[!unchanged_mask]
    new_names <- new_names[!unchanged_mask]
  }

  return(list(old = old_names, new = new_names))
}
