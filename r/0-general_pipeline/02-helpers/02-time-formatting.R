# script: time formatting
# description: utilities for deterministic elapsed time formatting.

#' @title Format elapsed time as a human-readable string
#' @description Converts elapsed seconds into a concise label suitable for CLI
#'   messages. Returns seconds, minutes+seconds, or hours+minutes depending on
#'   the magnitude.
#' @param elapsed_seconds Numeric scalar of non-negative elapsed seconds.
#' @return Character scalar formatted elapsed time.
#' @importFrom checkmate assert_number
#' @examples
#' format_elapsed_time(0.5)
#' format_elapsed_time(75)
#' format_elapsed_time(3661)
format_elapsed_time <- function(elapsed_seconds) {
  checkmate::assert_number(elapsed_seconds, lower = 0, finite = TRUE)

  constants <- get_pipeline_constants()
  seconds_per_minute <- constants$time_units$seconds_per_minute
  seconds_per_hour <- constants$time_units$seconds_per_hour

  if (elapsed_seconds < seconds_per_minute) {
    return(sprintf("%.1fs", elapsed_seconds))
  }

  total_seconds <- as.integer(round(elapsed_seconds))
  hours <- total_seconds %/% seconds_per_hour
  minutes <- (total_seconds %% seconds_per_hour) %/% seconds_per_minute
  seconds <- total_seconds %% seconds_per_minute

  if (hours > 0L) {
    return(sprintf("%dh %dm", hours, minutes))
  }

  return(sprintf("%dm %ds", minutes, seconds))
}
