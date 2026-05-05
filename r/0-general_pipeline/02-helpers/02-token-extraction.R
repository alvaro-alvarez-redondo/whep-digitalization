# script: token extraction
# description: helpers for parsing yearbook and commodity tokens.

#' @title extract yearbook token from parsed name parts
#' @description extracts token 2 and the first token matching a 4-digit year
#' from a parsed filename token vector, and joins them with an underscore.
#' @param parts character vector with no missing values and length greater than
#' or equal to one. validated with
#' `checkmate::check_character(min.len = 1, any.missing = false)`.
#' @return character scalar with combined yearbook tokens, or `NA_character_`
#' when token 2 is missing or no 4-digit year token is present.
#' @importFrom checkmate check_character
#' @examples
#' extract_yearbook(c("whep", "yb", "2020", "2021", "file.xlsx"))
extract_yearbook <- function(parts) {
  assert_or_abort(checkmate::check_character(
    parts,
    min.len = 1,
    any.missing = FALSE
  ))

  if (length(parts) < 2) {
    return(NA_character_)
  }

  year_pattern <- get_pipeline_constants()$patterns$yearbook_token_4digit
  year_token_idx <- which(grepl(year_pattern, parts))[1]

  if (is.na(year_token_idx)) {
    return(NA_character_)
  }

  return(paste(parts[2], parts[year_token_idx], sep = "_"))
}

#' @title extract commodity token suffix from parsed name parts
#' @description extracts tokens from index seven onward, removes the file
#' extension from the final token, and joins the result with underscores.
#' @param parts character vector with no missing values and length greater than
#' or equal to one. validated with
#' `checkmate::check_character(min.len = 1, any.missing = false)`.
#' @return character scalar with commodity tokens, or `NA_character_` when the
#' input has fewer than seven elements.
#' @importFrom checkmate check_character
#' @importFrom fs path_ext_remove
#' @examples
#' extract_commodity(c("a", "b", "c", "d", "e", "f", "rice", "grain.xlsx"))
extract_commodity <- function(parts) {
  assert_or_abort(checkmate::check_character(
    parts,
    min.len = 1,
    any.missing = FALSE
  ))

  constants <- get_pipeline_constants()
  start_index <- constants$tokens$commodity_start_index

  if (length(parts) >= start_index) {
    commodity_parts <- parts[seq.int(start_index, length(parts))]
    commodity_parts[length(commodity_parts)] <- fs::path_ext_remove(
      commodity_parts[length(commodity_parts)]
    )

    return(paste(commodity_parts, collapse = "_"))
  }

  return(NA_character_)
}
