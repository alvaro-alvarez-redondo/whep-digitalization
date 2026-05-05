#' @title Get fixed layer sheet order for lists export
#' @description Returns deterministic sheet order for column-centric list
#' export.
#' @return Character vector: `raw`, `clean`, `normalize`, `harmonize`.
get_lists_sheet_order <- function() {
  return(c("raw", "clean", "normalize", "harmonize"))
}

#' @title Map object name to layer sheet label
#' @description Infers the canonical sheet label from a layer object name.
#' @param object_name Character scalar object name.
#' @return Character scalar layer sheet label.
#' @importFrom checkmate assert_string
#' @importFrom cli cli_abort
infer_layer_sheet_name <- function(object_name) {
  checkmate::assert_string(object_name, min.chars = 1)

  if (grepl("_raw$", object_name)) {
    return("raw")
  }

  if (grepl("_clean$", object_name)) {
    return("clean")
  }

  if (grepl("_normalize$", object_name)) {
    return("normalize")
  }

  if (grepl("_harmonize$", object_name)) {
    return("harmonize")
  }

  cli::cli_abort(
    "unable to infer layer sheet name from object {.val {object_name}}"
  )
}
