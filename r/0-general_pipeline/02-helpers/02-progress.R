# script: progress reporting
# description: helpers for progress-aware mapping and the shared, cli-backed
# progress-bar presentation used by every pipeline stage runner.

#' @title is pipeline progress reporting enabled?
#' @description Resolves whether progress bars should render for the current
#' session. Progress is shown only when the `whep.progress.enabled` option is
#' `TRUE` (the default) **and** the session is interactive — non-interactive
#' runs (tests, the performance benchmark, batch `Rscript`) stay silent, which
#' matches the historical `handler_txtprogressbar(enable = interactive())`
#' behavior and keeps logs/test output clean.
#' @return Logical scalar.
#' @examples
#' pipeline_progress_enabled()
pipeline_progress_enabled <- function() {
  option_enabled <- isTRUE(getOption(
    get_pipeline_constants()$options$progress_enabled,
    TRUE
  ))

  return(option_enabled && interactive())
}

#' @title is the console using a dark background?
#' @description Resolves which progress-bar color palette to use. The
#' `whep.progress.dark` option wins when set (`TRUE`/`FALSE`); otherwise the
#' RStudio editor theme is queried via `rstudioapi::getThemeInfo()$dark` and
#' respected when available. **Defaults to `TRUE` (dark)** when neither is
#' conclusive — most consoles run a dark background, and the dark palette's
#' lighter shades stay readable there, whereas the light palette's mid-grey is
#' hard to read on dark. Set `options(whep.progress.dark = FALSE)` to force the
#' light palette. Fixed ANSI colors do not adapt to the terminal background, so
#' this switch is what keeps the muted text legible.
#' @return Logical scalar.
#' @examples
#' pipeline_progress_dark()
pipeline_progress_dark <- function() {
  override <- getOption(
    get_pipeline_constants()$options$progress_dark,
    NULL
  )
  if (!is.null(override)) {
    return(isTRUE(override))
  }

  rstudio_available <- requireNamespace("rstudioapi", quietly = TRUE) &&
    isTRUE(tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE))

  if (rstudio_available) {
    theme_info <- tryCatch(rstudioapi::getThemeInfo(), error = function(e) NULL)
    if (is.list(theme_info) && !is.null(theme_info$dark)) {
      return(isTRUE(theme_info$dark))
    }
  }

  return(TRUE)
}

#' @title build the progress handler for a pipeline stage
#' @description Constructs the cli-backed `progressr` handler used by a stage's
#' `with_progress()` block. All stages share one visual family (spinner, bar,
#' percent, live status message); they differ only by the stage label,
#' which is baked into the format as a string literal because
#' `progressr::progressor()` has no `name=` argument (so `{cli::pb_name}` would
#' render empty). The `import` stage additionally shows a throughput column.
#' Colors are theme-aware (see [pipeline_progress_dark()]): dark consoles get the
#' lighter bright-ANSI variants so the muted counts/elapsed text stays readable.
#' Returns the `"void"` handler when progress is disabled, and degrades to
#' `handler_txtprogressbar` if the cli handler is unavailable.
#' @param stage Character scalar stage key (e.g. `"import"`); falls back to
#' using the value itself as the label when it is not a known stage.
#' @param enable Logical scalar; defaults to `pipeline_progress_enabled()`.
#' @return A `progressr` handler object, or the character scalar `"void"`.
#' @importFrom checkmate assert_string assert_flag
#' @importFrom progressr handler_cli handler_txtprogressbar
#' @examples
#' \dontrun{
#' progressr::with_progress(
#'   { p <- progressr::progressor(steps = 3); for (i in 1:3) p() },
#'   handlers = pipeline_progress_handlers("import")
#' )
#' }
pipeline_progress_handlers <- function(
  stage,
  enable = pipeline_progress_enabled()
) {
  # Direct checkmate asserts (not assert_or_abort) so this helper has no
  # dependency on 02-assertions.R, letting the general stage source it before
  # the rest of 02-helpers/ to break the bootstrap chicken-and-egg.
  checkmate::assert_string(stage, min.chars = 1)
  checkmate::assert_flag(enable)

  if (!isTRUE(enable)) {
    return("void")
  }

  progress_constants <- get_pipeline_constants()$progress
  stage_label <- progress_constants$stage_labels[[stage]] %||% stage
  use_rate <- stage %in% progress_constants$rate_stages

  palette <- if (isTRUE(pipeline_progress_dark())) {
    progress_constants$palette$dark
  } else {
    progress_constants$palette$light
  }

  # Wrap a cli pb token in a color/style call, e.g. ("col_silver", "cli::pb_status")
  # -> "{cli::col_silver(cli::pb_status)}". Building the format here (rather than
  # storing finished strings in constants) keeps the colors theme-aware.
  paint <- function(color_fn, token) {
    sprintf("{cli::%s(%s)}", color_fn, token)
  }
  # The stage label shares the accent color with the percent (one unified blue),
  # kept bold so the name still stands out.
  label_segment <- paint(
    palette$accent,
    sprintf("cli::style_bold('%s')", stage_label)
  )

  in_progress_segments <- c(
    paint(palette$muted, "cli::pb_spin"),
    label_segment,
    "{cli::pb_bar}",
    paint(palette$accent, "cli::pb_percent"),
    if (isTRUE(use_rate)) paint(palette$muted, "cli::pb_rate"),
    paint(palette$muted, "cli::pb_status")
  )

  done_segments <- c(
    paint(palette$success, "cli::symbol$tick"),
    label_segment,
    paint(palette$success, "'done'"),
    paint(palette$muted, "paste0(cli::pb_current, '/', cli::pb_total)"),
    paint(palette$muted, "cli::pb_elapsed_clock")
  )

  # Degrade gracefully if the cli-backed handler is unavailable. cli/progressr
  # may be installed-but-not-attached at general-stage bootstrap time, so probe
  # the namespaces rather than the search path.
  cli_handler_available <- requireNamespace("cli", quietly = TRUE) &&
    requireNamespace("progressr", quietly = TRUE) &&
    exists("handler_cli", where = asNamespace("progressr"), inherits = FALSE)

  if (!cli_handler_available) {
    return(progressr::handler_txtprogressbar(
      width = progress_constants$fallback_bar_width,
      interval = progress_constants$update_interval,
      clear = FALSE,
      enable = TRUE
    ))
  }

  return(progressr::handler_cli(
    show_after = progress_constants$show_after,
    interval = progress_constants$update_interval,
    format = paste(in_progress_segments, collapse = " "),
    format_done = paste(done_segments, collapse = " "),
    clear = FALSE,
    enable = TRUE
  ))
}

#' @title run an expression under a pipeline stage progress bar
#' @description Wraps `progressr::with_progress()` with the shared stage handler,
#' the render gate, and the output-buffering settings that keep the bar from
#' flickering. The import stage relays progress in bursts as its parallel workers
#' finish; without buffering, progressr clears and redraws the bar around each
#' future's relayed stdout/conditions, so the bar appears to vanish and reappear.
#' Buffering relayed stdout and conditions (held until the stage ends) keeps the
#' bar on a single line for the whole stage. `expr` is evaluated lazily in the
#' caller's environment, so a `progressor()` created inside it binds to this bar.
#' @param expr Expression to evaluate under the progress bar.
#' @param stage Character scalar stage key (see [pipeline_progress_handlers()]).
#' @return The value of `expr`.
#' @importFrom checkmate assert_string
#' @importFrom progressr with_progress
#' @examples
#' \dontrun{
#' with_pipeline_progress({
#'   p <- progressr::progressor(steps = 3)
#'   for (i in 1:3) p()
#' }, "import")
#' }
with_pipeline_progress <- function(expr, stage) {
  checkmate::assert_string(stage, min.chars = 1)

  enabled <- pipeline_progress_enabled()

  progressr::with_progress(
    expr,
    handlers = pipeline_progress_handlers(stage, enable = enabled),
    enable = enabled,
    delay_stdout = TRUE,
    delay_conditions = "condition",
    delay_terminal = TRUE
  )
}

#' @title resolve the active console color palette (light/dark)
#' @description Returns the `constants$progress$palette` entry matching
#' [pipeline_progress_dark()], so plain console messages can share the progress
#' bar's colors instead of cli's default theme.
#' @return Named list of cli color specs (`muted` / `accent` / `success`).
pipeline_console_palette <- function() {
  progress_constants <- get_pipeline_constants()$progress
  if (isTRUE(pipeline_progress_dark())) {
    return(progress_constants$palette$dark)
  }
  return(progress_constants$palette$light)
}

#' @title color text with a pipeline palette role
#' @description Styles `text` with the cli call stored for `role` in the active
#' palette (a function name like `"col_cyan"`, or `"make_ansi_style('#a6c8ff')"`).
#' Lets console messages reuse the exact accent/success colors the bars use.
#' @param text Character scalar to style.
#' @param role One of `"muted"`, `"accent"`, `"success"`.
#' @return Styled character scalar (or plain `text` where the console lacks color).
#' @importFrom checkmate assert_string
pipeline_paint <- function(text, role) {
  checkmate::assert_string(role, min.chars = 1)
  # The palette stores each color as a cli expression spliced elsewhere into a
  # format string; here we evaluate it into a styling function to apply directly.
  styler <- eval(parse(text = paste0("cli::", pipeline_console_palette()[[role]])))
  return(styler(text))
}

#' @title pipeline info console line in the bar palette
#' @description Palette-matched replacement for `cli::cli_alert_info()`: an
#' accent-colored info symbol followed by `message`. Color inline values via
#' [pipeline_paint()] so they match the bars rather than cli's default theme.
#' @param message Character scalar message (may contain pre-styled segments).
#' @return Invisibly `NULL`; prints one line to the console.
#' @importFrom checkmate assert_string
pipeline_alert_info <- function(message) {
  checkmate::assert_string(message)
  cli::cat_line(paste0(
    pipeline_paint(cli::symbol$info, "accent"),
    " ",
    message
  ))
  return(invisible(NULL))
}

#' @title pipeline success console line in the bar palette
#' @description Palette-matched replacement for `cli::cli_alert_success()`: a
#' success-colored tick (the same symbol and color as the bars' completion tick)
#' followed by `message`.
#' @param message Character scalar message (may contain pre-styled segments).
#' @return Invisibly `NULL`; prints one line to the console.
#' @importFrom checkmate assert_string
pipeline_alert_success <- function(message) {
  checkmate::assert_string(message)
  cli::cat_line(paste0(
    pipeline_paint(cli::symbol$tick, "success"),
    " ",
    message
  ))
  return(invisible(NULL))
}

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

  #' Resolve Progress Message
  #'
  #' Formats a progress message by dispatching to a custom function or applying
  #' a `sprintf()` template with the current index and total step count.
  #'
  #' @param item The current item being processed.
  #' @param index Integer index of the current item.
  #' @param total_steps Total number of items in the iteration.
  #' @return A formatted character string or `NULL`.
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
