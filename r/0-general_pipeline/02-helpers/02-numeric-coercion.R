# script: numeric coercion
# description: numeric conversion helpers for pipeline data.

#' @title coerce vector values to numeric safely
#' @description converts an atomic vector to numeric using a stable character
#' intermediary. empty strings are treated as missing values and non-numeric
#' values are converted to `NA_real_` without raising warnings.
#' @param x atomic vector with length greater than or equal to one. validated
#' with `checkmate::check_atomic(min.len = 1, any.missing = TRUE)`.
#' @return numeric vector with the same length as `x`.
#' @importFrom checkmate check_atomic
#' @examples
#' coerce_numeric_safe(c("1", " 2.5 ", "", "abc"))
coerce_numeric_safe <- function(x) {
  assert_or_abort(checkmate::check_atomic(
    x,
    min.len = 1,
    any.missing = TRUE
  ))

  if (
    (is.double(x) || is.integer(x)) &&
      is.null(attr(x, "class", exact = TRUE))
  ) {
    return(as.numeric(x))
  }

  if (is.character(x)) {
    return(suppressWarnings(as.numeric(x)))
  }

  return(suppressWarnings(as.numeric(as.character(x))))
}
