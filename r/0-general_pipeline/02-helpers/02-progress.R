# script: progress reporting
# description: helpers for progress-aware mapping.

#' @title map with optional progressr reporting
#' @description applies a function over an input vector with optional progress
#' updates powered by `progressr`. the helper respects global progressr
#' configuration and can be disabled via argument or option.
#' @param x vector or list to iterate over.
#' @param .f function applied to each element of `x`.
#' @param ... additional arguments passed to `.f`.
#' @param message_template optional character scalar format string passed to
#' `sprintf()`. supports `%d` placeholders for current index and total steps.
#' @param message_fn optional function with signature
#' `function(item, index, total_steps)` returning a character scalar progress
#' message.
#' @param enable_progress logical scalar indicating whether progress updates are
#' emitted. defaults to `getOption("whep.progress.enabled", TRUE)`.
#' @return list with one element per input item, matching `purrr::map()`
#' semantics.
#' @importFrom checkmate check_atomic_vector check_flag check_function check_list check_string
#' @importFrom progressr progressor with_progress
#' @importFrom purrr imap map
#' @examples
#' map_with_progress(1:3, \(x) x * 2, enable_progress = FALSE)
map_with_progress <- function(
  x,
  .f,
  ...,
  message_template = NULL,
  message_fn = NULL,
  enable_progress = getOption(
    get_pipeline_constants()$options$progress_enabled,
    TRUE
  )
) {
  list_check_result <- checkmate::check_list(x, min.len = 0, any.missing = TRUE)
  atomic_check_result <- checkmate::check_atomic_vector(
    x,
    min.len = 0,
    any.missing = TRUE
  )

  input_check_result <- if (isTRUE(list_check_result)) {
    TRUE
  } else {
    atomic_check_result
  }

  assert_or_abort(input_check_result)
  assert_or_abort(checkmate::check_function(.f))
  assert_or_abort(checkmate::check_flag(enable_progress))

  if (!is.null(message_template)) {
    assert_or_abort(checkmate::check_string(message_template, min.chars = 1))
  }

  if (!is.null(message_fn)) {
    assert_or_abort(checkmate::check_function(message_fn))
  }

  total_steps <- length(x)

  if (!enable_progress || total_steps == 0) {
    return(purrr::map(x, \(item) .f(item, ...)))
  }

  resolve_progress_message <- function(item, index, total_steps) {
    progress_message <- NULL

    if (!is.null(message_fn)) {
      progress_message <- message_fn(item, index, total_steps)
    } else if (!is.null(message_template)) {
      progress_message <- sprintf(message_template, index, total_steps)
    }

    if (is.null(progress_message)) {
      return(NULL)
    }

    assert_or_abort(checkmate::check_string(progress_message, min.chars = 1))

    return(progress_message)
  }

  return(progressr::with_progress({
    progress <- progressr::progressor(steps = total_steps)

    purrr::imap(x, \(item, index) {
      progress_message <- resolve_progress_message(item, index, total_steps)

      if (is.null(progress_message)) {
        progress()
      } else {
        progress(progress_message)
      }

      .f(item, ...)
    })
  }))
}
