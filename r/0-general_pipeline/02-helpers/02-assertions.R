# script: validation helpers
# description: reusable validation wrappers for CLI aborts.

#' @title assert checkmate validation results with cli errors
#' @description lightweight wrapper that checks the output of a
#' `checkmate::check_*` call. when the check returns a character error message
#' (i.e. validation failed), the function aborts with a structured cli error.
#' passes through `TRUE` results with minimal overhead.
#' @param check_result logical `TRUE` or character error string returned by a
#' `checkmate::check_*` function.
#' @return invisible `TRUE` when validation succeeds.
#' @importFrom cli cli_abort
#' @examples
#' assert_or_abort(checkmate::check_string("ok"))
assert_or_abort <- function(check_result) {
  if (!isTRUE(check_result)) {
    cli::cli_abort(check_result)
  }
  return(invisible(TRUE))
}
