# script: dependency audit
# description: detects namespace-qualified package usage in scripts.

#' @title collect namespaced dependencies
#' @description scan project scripts for namespace-qualified calls (`pkg::fn`) and
#' return the unique package names referenced.
#' @param scripts_root character scalar path to the script root directory.
#' defaults to `here::here("r")`.
#' @return character vector of unique package names discovered in script files.
#' @importFrom checkmate check_string check_directory_exists
#' @importFrom fs dir_ls
#' @examples
#' \dontrun{
#' collect_namespaced_dependencies()
#' }
collect_namespaced_dependencies <- function(
  scripts_root = here::here("r")
) {
  abort_on_checkmate_failure(checkmate::check_string(
    scripts_root,
    min.chars = 1
  ))
  abort_on_checkmate_failure(checkmate::check_directory_exists(scripts_root))

  constants <- get_pipeline_constants()
  namespace_pattern <- constants$patterns$namespace_qualified

  script_files <- fs::dir_ls(
    path = scripts_root,
    recurse = TRUE,
    type = "file",
    glob = "*.R"
  )

  package_names <- script_files |>
    unname() |>
    lapply(function(script_file) {
      script_lines <- readLines(script_file, warn = FALSE, encoding = "UTF-8")
      matches <- regmatches(
        script_lines,
        gregexpr(namespace_pattern, script_lines, perl = TRUE)
      )

      package_candidates <- unlist(matches, use.names = FALSE)

      if (length(package_candidates) == 0) {
        return(character(0))
      }

      return(sub("::$", "", package_candidates))
    }) |>
    unlist(use.names = FALSE) |>
    unique() |>
    sort()

  return(package_names)
}

#' @title audit dependency registry
#' @description compare the declared dependency registry to namespaced package
#' usage found in project scripts.
#' @param packages declared package registry.
#' @param scripts_root character scalar path to the script root directory.
#' @return named list with `declared`, `used`, `unused`, and `missing` package
#' vectors.
#' @importFrom checkmate check_character check_string check_directory_exists
#' @examples
#' \dontrun{
#' audit_dependency_registry(required_packages)
#' }
audit_dependency_registry <- function(
  packages = required_packages,
  scripts_root = here::here("r")
) {
  abort_on_checkmate_failure(checkmate::check_character(
    packages,
    any.missing = FALSE,
    min.len = 1
  ))
  abort_on_checkmate_failure(checkmate::check_string(
    scripts_root,
    min.chars = 1
  ))
  abort_on_checkmate_failure(checkmate::check_directory_exists(scripts_root))

  declared_packages <- sort(unique(packages))
  used_packages <- collect_namespaced_dependencies(scripts_root = scripts_root)

  dependency_audit <- list(
    declared = declared_packages,
    used = used_packages,
    unused = setdiff(declared_packages, used_packages),
    missing = setdiff(used_packages, declared_packages)
  )

  return(dependency_audit)
}
