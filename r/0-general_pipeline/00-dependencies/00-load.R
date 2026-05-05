# script: dependency loading
# description: attaches required packages with clean startup output.

#' @title load dependencies
#' @description validates a character vector of package names and attaches each package with
#' startup messages suppressed to keep project logs clean and deterministic.
#' @param packages character vector. must be non-missing, non-empty, and contain at least
#' one package name.
#' @return invisible null. used for side effects by attaching packages to the session.
#' @importFrom checkmate check_character
#' @importFrom purrr walk
#' @importFrom cli cli_abort
#' @importFrom base require
#' @examples
#' load_dependencies(c("stats", "utils"))
load_dependencies <- function(packages) {
  abort_on_checkmate_failure(checkmate::check_character(
    packages,
    any.missing = FALSE,
    min.len = 1
  ))

  attached_packages <- sub(
    "^package:",
    "",
    grep("^package:", search(), value = TRUE)
  )
  packages_to_load <- setdiff(packages, attached_packages)

  if (length(packages_to_load) == 0L) {
    return(invisible(NULL))
  }

  for (package_name in packages_to_load) {
    package_loaded <- suppressPackageStartupMessages(
      require(package_name, character.only = TRUE, quietly = TRUE)
    )

    if (!isTRUE(package_loaded)) {
      cli::cli_abort("failed to attach package `{package_name}`.")
    }
  }

  return(invisible(NULL))
}
