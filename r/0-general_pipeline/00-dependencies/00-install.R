# script: dependency installation
# description: validates and installs missing package dependencies.

#' @title check dependencies
#' @description validates a character vector of package names, identifies missing packages,
#' and installs any package that is not currently available via namespace lookup.
#' this function is defensive and installs packages silently when required.
#' @param packages character vector. must be non-missing, non-empty, and contain at least
#' one package name.
#' @return character vector of missing package names. returns an empty character vector when
#' all dependencies are already installed.
#' @importFrom checkmate check_character
#' @importFrom base requireNamespace
#' @importFrom cli cli_alert_info cli_warn
#' @importFrom renv install
#' @examples
#' missing_packages <- check_dependencies(c("stats", "utils"))
#' missing_packages
check_dependencies <- function(packages) {
  abort_on_checkmate_failure(checkmate::check_character(
    packages,
    any.missing = FALSE,
    min.len = 1
  ))

  already_loaded <- vapply(packages, isNamespaceLoaded, logical(1))
  candidates <- packages[!already_loaded]

  if (length(candidates) == 0L) {
    return(character(0))
  }

  package_availability <- vapply(
    candidates,
    FUN = requireNamespace,
    FUN.VALUE = logical(1),
    quietly = TRUE
  )

  missing_packages <- unique(candidates[!package_availability])

  if (length(missing_packages) > 0) {
    cli::cli_warn(c(
      "installing missing dependencies with renv",
      "i" = "missing packages: {toString(missing_packages)}"
    ))

    renv::install(missing_packages)

    cli::cli_alert_info("dependency installation completed")
  }

  return(missing_packages)
}
