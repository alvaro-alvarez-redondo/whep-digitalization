# script: string normalization
# description: string cleaning helpers for pipeline normalization.

#' @title fast internal string normalization
#' @description converts an atomic vector to lowercase ascii, removes
#' non-alphanumeric characters except spaces, and squishes repeated spaces.
#' skips input validation for performance in hot paths. callers must ensure
#' the input is a valid atomic vector.
#' @param x atomic vector to normalize. coerced to character internally.
#' @return character vector with normalize lowercase ascii text.
#' @importFrom stringi stri_trans_general stri_replace_all_regex stri_trim_both
#' @importFrom data.table uniqueN
normalize_string_impl <- function(x) {
  constants <- get_pipeline_constants()
  non_alnum_pattern <- constants$patterns$normalize_non_alnum
  normalize_pattern <- constants$patterns$normalize_already_clean

  values_chr <- as.character(x)
  non_na_idx <- !is.na(values_chr)

  if (!any(non_na_idx)) {
    return(values_chr)
  }

  values_non_na <- values_chr[non_na_idx]
  values_n <- length(values_non_na)

  use_unique_path <- FALSE
  perf_cfg <- constants$performance
  if (values_n >= perf_cfg$normalize_unique_min_n) {
    sample_n <- min(values_n, perf_cfg$normalize_unique_sample_n)
    unique_ratio <- data.table::uniqueN(values_non_na[seq_len(sample_n)]) /
      sample_n
    use_unique_path <- unique_ratio <= perf_cfg$normalize_unique_ratio_threshold
  }

  if (isTRUE(use_unique_path)) {
    unique_values <- unique(values_non_na)
    if (all(stringi::stri_detect_regex(unique_values, normalize_pattern))) {
      values_chr[non_na_idx] <- unique_values[match(
        values_non_na,
        unique_values
      )]
      return(values_chr)
    }

    normalize_unique <- stringi::stri_trans_general(
      unique_values,
      "Latin-ASCII; Lower"
    )
    normalize_unique <- stringi::stri_replace_all_regex(
      normalize_unique,
      non_alnum_pattern,
      " "
    )
    normalize_unique <- stringi::stri_trim_both(normalize_unique)
    values_chr[non_na_idx] <- normalize_unique[match(
      values_non_na,
      unique_values
    )]
    return(values_chr)
  }

  normalize_values <- stringi::stri_trans_general(
    values_non_na,
    "Latin-ASCII; Lower"
  )
  normalize_values <- stringi::stri_replace_all_regex(
    normalize_values,
    non_alnum_pattern,
    " "
  )
  values_chr[non_na_idx] <- stringi::stri_trim_both(normalize_values)

  return(values_chr)
}

#' @title normalize free text into lowercase ascii
#' @description converts input text to lowercase ascii, removes non-alphanumeric
#' characters except spaces, and squishes repeated spaces to one separator.
#' @param string atomic vector with length greater than or equal to one.
#' validated with `checkmate::check_atomic(min.len = 1, any.missing = true)`.
#' @return character vector with normalize lowercase ascii text.
#' @importFrom checkmate check_atomic
#' @examples
#' normalize_string("forest! data 2024")
normalize_string <- function(string) {
  checkmate::assert_atomic_vector(
    string,
    min.len = 1,
    any.missing = TRUE
  )
  normalize_string_impl(string)
}

#' @title fast internal footnote string normalization
#' @description converts footnote text to lowercase ascii and removes characters
#' that are not alphanumeric, spaces, or footnote-safe punctuation
#' (`;`, `/`, `*`, `(`, `)`, `.`, `,`, `-`, `#`, `%`, `:`).
#' unlike `normalize_string_impl`, this preserves the special characters
#' commonly found in footnotes (reference markers, separators, parenthetical
#' labels). skips input validation for performance in hot paths.
#' @param x atomic vector to normalize. coerced to character internally.
#' @return character vector with normalize lowercase ascii footnote text.
#' @importFrom stringi stri_trans_general stri_replace_all_regex stri_trim_both
clean_footnote_impl <- function(x) {
  constants <- get_pipeline_constants()
  footnote_pattern <- constants$patterns$footnote_non_alnum

  out <- stringi::stri_trans_general(x, "Latin-ASCII; Lower")
  out <- stringi::stri_replace_all_regex(out, footnote_pattern, " ")
  stringi::stri_trim_both(out)
}

#' @title normalize footnote text into lowercase ascii
#' @description converts footnote text to lowercase ascii, removing characters
#' that are not alphanumeric, spaces, or common footnote punctuation while
#' preserving reference markers (`;`, `/`, `*`, `(`, `)`, `.`, `,`, `-`, `#`,
#' `%`, `:`). use this instead of `normalize_string()` for footnotes columns to
#' avoid stripping meaningful symbols.
#' @param x atomic vector with length greater than or equal to one. validated
#' with `checkmate::assert_atomic_vector(min.len = 1, any.missing = TRUE)`.
#' @return character vector with normalize lowercase ascii footnote text.
#' @importFrom checkmate assert_atomic_vector
#' @examples
#' clean_footnote("Note 1/ Official data (revised); 50% estimate")
clean_footnote <- function(x) {
  checkmate::assert_atomic_vector(x, min.len = 1, any.missing = TRUE)
  clean_footnote_impl(x)
}

#' @title normalize file-friendly names
#' @description normalizes text and replaces spaces with underscores for
#' deterministic filename stems. missing and empty outputs are replaced by
#' `"unknown"`.
#' @param filename atomic vector with length greater than or equal to one.
#' validated with `checkmate::check_atomic(min.len = 1, any.missing = true)`.
#' @return character vector containing lowercase ascii filename stems.
#' @importFrom checkmate check_atomic
#' @importFrom stringr str_replace_all
#' @examples
#' normalize_filename("food balance sheet")
normalize_filename <- function(filename) {
  assert_or_abort(checkmate::check_atomic(
    filename,
    min.len = 1,
    any.missing = TRUE
  ))

  constants <- get_pipeline_constants()
  unknown_label <- constants$defaults$unknown_filename

  normalize_filename <- filename |>
    normalize_string() |>
    stringr::str_replace_all(" ", "_")

  normalize_filename[
    is.na(normalize_filename) | normalize_filename == ""
  ] <- unknown_label

  return(normalize_filename)
}
