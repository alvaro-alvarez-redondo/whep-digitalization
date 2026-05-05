# file: metadata helpers for import pipeline
build_empty_file_metadata <- function() {
  return(data.table::data.table(
    file_path = character(),
    file_name = character(),
    commodity = character(),
    yearbook = character(),
    is_ascii = logical(),
    error_message = character()
  ))
}

extract_file_metadata <- function(file_paths) {
  assert_or_abort(checkmate::check_character(
    file_paths,
    any.missing = FALSE,
    min.len = 1
  ))

  file_name <- fs::path_file(file_paths)
  is_ascii <- stringi::stri_enc_isascii(file_name)

  name_parts <- strsplit(file_name, "_", fixed = TRUE)
  year_pattern <- get_pipeline_constants()$patterns$yearbook_token_4digit

  metadata_pairs <- vapply(
    name_parts,
    function(parts) {
      year_token_idx <- which(grepl(year_pattern, parts))[1]
      yb <- if (length(parts) >= 2 && !is.na(year_token_idx)) {
        paste(parts[2], parts[year_token_idx], sep = "_")
      } else {
        NA_character_
      }
      pr <- if (length(parts) > 6) {
        commodity_parts <- parts[7:length(parts)]
        commodity_parts[length(commodity_parts)] <- fs::path_ext_remove(
          commodity_parts[length(commodity_parts)]
        )
        paste(commodity_parts, collapse = "_")
      } else {
        NA_character_
      }
      c(yb, pr)
    },
    character(2)
  )
  yearbook <- metadata_pairs[1L, ]
  commodity <- metadata_pairs[2L, ]

  metadata <- data.table::data.table(
    file_path = as.character(file_paths),
    file_name = file_name,
    commodity = commodity,
    yearbook = yearbook,
    is_ascii = is_ascii,
    error_message = ifelse(
      !is_ascii,
      paste0("non-ascii file name detected: ", file_name),
      NA_character_
    )
  )

  return(metadata)
}
