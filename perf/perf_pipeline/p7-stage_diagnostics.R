#' @title Stage diagnostic module
#' @description Stage-level and global diagnostic builders for benchmark
#'   complexity outputs.
#' @keywords internal
#' @noRd
NULL

# ── 7. stage diagnostics ─────────────────────────────────────────────────────

# ── 7a. scaling descriptions ─────────────────────────────────────────────────

#' @title Describe scaling behavior
#' @description Return a human-readable interpretation for a complexity class.
#' @param class_label A character scalar complexity label.
#' @return A character scalar description.
describe_scaling <- function(class_label) {
  switch(
    class_label,
    "O(1)" = "constant time: runtime is independent of input size.",
    "O(log n)" = "logarithmic: runtime grows very slowly; doubles only when n squares.",
    "O(n)" = "linear: runtime scales proportionally with input size.",
    "O(n log n)" = "linearithmic: near-linear; acceptable for sort-heavy operations.",
    "O(n^2)" = "quadratic: runtime quadruples when n doubles; avoid for n > 10k.",
    "O(n^3)" = "cubic: runtime grows extremely fast; critical bottleneck above n ~ 1k.",
    "unknown" = "insufficient data to determine scaling behaviour.",
    "ERROR" = "benchmark failed; complexity class could not be estimated.",
    sprintf("unrecognised complexity class: '%s'.", class_label)
  )
}

# ── 7b. optimization signals ─────────────────────────────────────────────────

#' @title Generate optimization signal
#' @description Return an optimization recommendation for a function based on
#'   fitted complexity class.
#' @param class_label A character scalar complexity label.
#' @param fn_name A character scalar function identifier.
#' @return A character scalar recommendation.
optimization_signal <- function(class_label, fn_name) {
  switch(
    class_label,
    "O(1)" = sprintf(
      "%s shows constant-time behaviour — no optimization needed.",
      fn_name
    ),
    "O(log n)" = sprintf(
      "%s shows logarithmic scaling — generally efficient; monitor at very large n.",
      fn_name
    ),
    "O(n)" = sprintf(
      "%s is linear — verify that the implementation avoids hidden O(n) passes",
      fn_name
    ),
    "O(n log n)" = sprintf(
      paste0(
        "%s is linearithmic — acceptable if caused by sorting; consider",
        " pre-sorting or index-based lookup if called frequently."
      ),
      fn_name
    ),
    "O(n^2)" = sprintf(
      paste0(
        "%s is QUADRATIC — high priority for optimization. Look for nested",
        " loops or non-indexed joins and replace with vectorized or hash-based",
        " operations (e.g. data.table keyed joins)."
      ),
      fn_name
    ),
    "O(n^3)" = sprintf(
      paste0(
        "%s is CUBIC — critical bottleneck. This function is unlikely to",
        " scale to commodityion data sizes. Redesign the algorithm immediately."
      ),
      fn_name
    ),
    "unknown" = sprintf(
      paste0(
        "%s: could not fit a complexity model — collect more data points",
        " or check that the function produces consistent timing measurements."
      ),
      fn_name
    ),
    "ERROR" = sprintf(
      "%s: benchmark failed — fix the error before drawing conclusions.",
      fn_name
    ),
    sprintf("%s: unrecognised class '%s'.", fn_name, class_label)
  )
}

# ── 7c. bottleneck ranking ────────────────────────────────────────────────────

#' @title Rank bottlenecks
#' @description Sort complexity rows by worst complexity rank and slope, then
#'   return the top entries.
#' @param complexity_dt A data.table with complexity ranking columns.
#' @param top_n An integer scalar count of rows to return.
#' @return A data.table containing top bottleneck rows.
rank_bottlenecks <- function(complexity_dt, top_n = 3L) {
  ranked <- complexity_dt[order(-complexity_rank, -slope_per_n, na.last = TRUE)]
  head(ranked, top_n)
}

# ── 7d. per-stage diagnostic ──────────────────────────────────────────────────

#' @title Diagnose stage
#' @description Build a structured diagnostic object for one stage based on
#'   fitted complexity results.
#' @param stage_id A character scalar stage identifier.
#' @param stage_results A list returned by run_stage_analysis().
#' @param cfg A named list from get_analysis_config().
#' @return A named list:
#'   \describe{
#'     \item{stage_id}{character — stage label}
#'     \item{dominant_class}{character — worst complexity class in this stage}
#'     \item{scaling_description}{character — human-readable scaling description}
#'     \item{bottlenecks}{data.table — top-N most expensive functions}
#'     \item{optimization_signals}{named character vector — signal per function}
#'     \item{is_concern}{logical — TRUE when dominant class is O(n^2) or worse}
#'     \item{complexity_dt}{data.table — full per-function complexity table}
#'   }
diagnose_stage <- function(stage_id, stage_results, cfg) {
  cdt <- stage_results$complexity

  dominant_rows <- cdt[isTRUE(dominant_in_stage) | dominant_in_stage == TRUE]
  dominant_class <- if (nrow(dominant_rows) > 0L) {
    dominant_rows$best_class[[1L]]
  } else if (nrow(cdt) > 0L) {
    cdt$best_class[[1L]]
  } else {
    "unknown"
  }

  bottlenecks <- rank_bottlenecks(cdt, top_n = cfg$top_n_bottlenecks)

  signals <- setNames(
    vapply(
      seq_len(nrow(cdt)),
      function(i) optimization_signal(cdt$best_class[[i]], cdt$fn_name[[i]]),
      character(1)
    ),
    cdt$fn_name
  )

  concern_rank <- .complexity_order[["O(n^2)"]]
  is_concern <- isTRUE(
    .complexity_order[dominant_class] >= concern_rank
  )

  list(
    stage_id = stage_id,
    dominant_class = dominant_class,
    scaling_description = describe_scaling(dominant_class),
    bottlenecks = bottlenecks,
    optimization_signals = signals,
    is_concern = is_concern,
    complexity_dt = cdt
  )
}

# ── 7e. global (cross-stage) diagnostic ──────────────────────────────────────

#' @title Build global diagnostic
#' @description Aggregate stage diagnostics into a unified cross-stage
#'   diagnostic summary.
#' @param stage_diagnostics A named list of diagnose_stage() outputs.
#' @return A named list:
#'   \describe{
#'     \item{overall_class}{character — worst complexity class across all stages}
#'     \item{overall_scaling_description}{character — scaling description for
#'       the overall class}
#'     \item{pipeline_bottleneck}{character — name of the globally worst function}
#'     \item{stage_summary}{data.table — per-stage dominant class and concern flag}
#'     \item{ranked_stages}{character vector — stages ranked from worst to best
#'       complexity}
#'     \item{stage_diagnostics}{named list — original per-stage diagnostics}
#'   }
build_global_diagnostic <- function(stage_diagnostics) {
  stage_ids <- names(stage_diagnostics)
  dom_classes <- vapply(
    stage_diagnostics,
    function(d) d$dominant_class,
    character(1)
  )
  concern_flags <- vapply(
    stage_diagnostics,
    function(d) isTRUE(d$is_concern),
    logical(1)
  )
  dom_ranks <- vapply(
    dom_classes,
    function(cl) {
      r <- .complexity_order[cl]
      if (is.na(r)) .complexity_order[["unknown"]] else r
    },
    integer(1)
  )

  stage_summary <- data.table::data.table(
    stage = stage_ids,
    dominant_class = dom_classes,
    complexity_rank = dom_ranks,
    is_concern = concern_flags
  )[order(-complexity_rank)]

  overall_idx <- which.max(dom_ranks)
  overall_class <- dom_classes[[overall_idx]]

  all_cdt <- data.table::rbindlist(
    lapply(stage_diagnostics, function(d) d$complexity_dt),
    fill = TRUE
  )
  if (nrow(all_cdt) > 0L) {
    top_row <- rank_bottlenecks(all_cdt, top_n = 1L)
    pipeline_bottleneck <- if (nrow(top_row) > 0L) {
      top_row$fn_name[[1L]]
    } else {
      NA_character_
    }
  } else {
    pipeline_bottleneck <- NA_character_
  }

  ranked_stages <- stage_summary$stage

  list(
    overall_class = overall_class,
    overall_scaling_description = describe_scaling(overall_class),
    pipeline_bottleneck = pipeline_bottleneck,
    stage_summary = stage_summary,
    ranked_stages = ranked_stages,
    stage_diagnostics = stage_diagnostics
  )
}
