# script: dependency validation
# description: provides validation helpers for dependency checks

#' @title abort on failed checkmate checks
#' @description convert a `checkmate::check_*` result into a cli abort when validation fails.
#' this keeps user-facing errors consistent and structured.
#' @param check_result logical true or character scalar returned by a `checkmate::check_*`
#' validator.
#' @return invisible true when validation passes.
#' @importFrom checkmate assert check_true check_string
#' @importFrom cli cli_abort
#' @examples
#' abort_on_checkmate_failure(checkmate::check_true(TRUE))
abort_on_checkmate_failure <- function(check_result) {
  checkmate::assert(
    checkmate::check_true(check_result),
    checkmate::check_string(check_result, min.chars = 1)
  )

  if (!isTRUE(check_result)) {
    cli::cli_abort(check_result)
  }

  return(invisible(TRUE))
}
