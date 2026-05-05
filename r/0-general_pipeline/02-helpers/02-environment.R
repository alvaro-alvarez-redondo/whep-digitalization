# script: environment assignment
# description: helpers for deterministic environment assignment.

#' @title Assign named values into an environment
#' @description Validates a named list and assigns each element to `env` using
#' deterministic one-by-one writes.
#' @param values Named list of objects to assign.
#' @param env Environment receiving assigned values.
#' @return Invisibly returns `TRUE`.
#' @importFrom checkmate assert_environment assert_list
#' @importFrom purrr iwalk
#' @examples
#' temp_env <- new.env(parent = emptyenv())
#' assign_environment_values(list(answer = 42L), temp_env)
assign_environment_values <- function(values, env) {
  assert_or_abort(checkmate::check_list(
    values,
    names = "named",
    any.missing = TRUE
  ))
  assert_or_abort(checkmate::check_environment(env))

  purrr::iwalk(values, \(value, object_name) {
    assign(object_name, value, envir = env)
  })

  return(invisible(TRUE))
}
