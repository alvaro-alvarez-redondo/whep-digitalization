#' @title Orchestration module
#' @description Bootstrap and orchestration helpers for the performance
#'   analysis framework.
#' @keywords internal
#' @noRd
NULL

# ── prevent pipeline auto-execution ─────────────────────────────────────────

options(
  whep.run_pipeline.auto = FALSE,
  whep.run_general_pipeline.auto = FALSE,
  whep.run_import_pipeline.auto = FALSE,
  whep.run_postpro_pipeline.auto = FALSE,
  whep.run_export_pipeline.auto = FALSE,
  whep.checkpointing.enabled = FALSE
)

# ── resolve project root ─────────────────────────────────────────────────────

.perf_project_root <- tryCatch(
  here::here(),
  error = function(e) {
    normalizePath(file.path(getwd(), ".."), mustWork = FALSE)
  }
)

# ── helpers ───────────────────────────────────────────────────────────────────

#' @title Source pipeline script
#' @description Internal helper to source a pipeline script from the scripts
#'   directory using a relative path.
#' @param relative_path A character scalar relative path under R/.
#' @return Invisible logical scalar indicating whether sourcing succeeded.
#' @keywords internal
#' @noRd
.source_pipeline_script <- function(relative_path) {
  abs_path <- file.path(.perf_project_root, "r", relative_path)
  if (!file.exists(abs_path)) {
    warning(sprintf("pipeline script not found, skipping: %s", abs_path))
    return(invisible(FALSE))
  }
  tryCatch(
    {
      source(abs_path, echo = FALSE, local = FALSE)
      invisible(TRUE)
    },
    error = function(e) {
      warning(sprintf(
        "failed to source %s: %s",
        relative_path,
        conditionMessage(e)
      ))
      invisible(FALSE)
    }
  )
}

#' @title Source performance script
#' @description Internal helper to source a module script from the perf
#'   directory.
#' @param filename A character scalar module filename under perf/.
#' @return Invisible TRUE when sourcing succeeds.
#' @keywords internal
#' @noRd
.source_perf_script <- function(filename) {
  abs_path <- file.path(.perf_project_root, "perf", "perf_pipeline", filename)
  if (!file.exists(abs_path)) {
    stop(sprintf("perf sub-module not found: %s", abs_path))
  }
  source(abs_path, echo = FALSE, local = FALSE)
  invisible(TRUE)
}

# ── load pipeline helper functions ────────────────────────────────────────────

.source_pipeline_script("0-general_pipeline/00-dependencies/00-validation.R")
.source_pipeline_script("0-general_pipeline/00-dependencies/00-install.R")
.source_pipeline_script("0-general_pipeline/00-dependencies/00-load.R")
.source_pipeline_script("0-general_pipeline/00-dependencies/00-audit.R")
.source_pipeline_script("0-general_pipeline/01-setup/01-constants.R")
.source_pipeline_script("0-general_pipeline/01-setup/01-config.R")
.source_pipeline_script("0-general_pipeline/01-setup/01-directories.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-assertions.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-time-formatting.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-string-normalization.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-numeric-coercion.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-token-extraction.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-data-table.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-export-validation.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-config-accessors.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-progress.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-sorting.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-environment.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-checkpoints.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-data-cleaning.R")
.source_pipeline_script("0-general_pipeline/02-helpers/02-io-cache.R")
.source_pipeline_script("1-import_pipeline/10-file_io/10-metadata.R")
.source_pipeline_script("1-import_pipeline/10-file_io/10-discovery.R")
.source_pipeline_script("1-import_pipeline/11-reading/11-read-utils.R")
.source_pipeline_script("1-import_pipeline/11-reading/11-sheet-read.R")
.source_pipeline_script("1-import_pipeline/11-reading/11-batching.R")
.source_pipeline_script("1-import_pipeline/12-transform/12-transform-utils.R")
.source_pipeline_script("1-import_pipeline/12-transform/12-reshape.R")
.source_pipeline_script("1-import_pipeline/12-transform/12-processing.R")
.source_pipeline_script("1-import_pipeline/13-output/13-validate.R")
.source_pipeline_script("1-import_pipeline/13-output/13-output.R")
.source_pipeline_script("2-postpro_pipeline/21-postpro_utilities/21-stage-definitions.R")
.source_pipeline_script("2-postpro_pipeline/21-postpro_utilities/21-output-roots.R")
.source_pipeline_script("2-postpro_pipeline/24-standardize_units/24-rules-setup.R")
.source_pipeline_script("2-postpro_pipeline/24-standardize_units/24-standardize-engine.R")
.source_pipeline_script("2-postpro_pipeline/24-standardize_units/24-standardize-orchestration.R")
.source_pipeline_script("3-export_pipeline/31-export_lists.R")

# ── load perf sub-modules (p0 ... p8) ────────────────────────────────────────

.source_perf_script("p0-dependencies.R")
ensure_perf_dependencies()

.source_perf_script("p1-setup.R")
.source_perf_script("p2-synthetic_data.R")
.source_perf_script("p3-complexity_models.R")
.source_perf_script("p4-timing_harness.R")
.source_perf_script("p5-workload_generators.R")
.source_perf_script("p6-execution_engine.R")
.source_perf_script("p7-stage_diagnostics.R")
.source_perf_script("p8-reporting.R")

# ── main entry point ──────────────────────────────────────────────────────────

#' @title Run big-O analysis
#' @description Execute the full performance workflow, including benchmark
#'   execution, complexity fitting, diagnostics, reporting, Markdown export, and
#'   persistence.
#'
#'   stage-level results are available under `result$by_stage[[stage_id]]` and
#'   stage diagnostics under `result$stage_diagnostics[[stage_id]]`.
#'
#' @param cfg A named list of analysis configuration values.
#' @param output_dir A character scalar output directory override.
#' @param quiet A logical scalar verbosity flag.
#' @return An invisible named list:
#'   \describe{
#'     \item{by_stage}{named list — per-stage raw/summary/complexity results}
#'     \item{raw}{data.table — all timing observations}
#'     \item{summary}{data.table — per-(function, n) statistics}
#'     \item{complexity}{data.table — per-function complexity classes}
#'     \item{stage_diagnostics}{named list — per-stage diagnostic objects}
#'     \item{global_diagnostic}{list — unified pipeline diagnostic}
#'     \item{markdown_path}{character — path of general project markdown summary}
#'     \item{markdown_paths}{named character vector — paths of all markdown reports}
#'     \item{qs_path}{character — path of written .qs file}
#'   }
run_big_o_analysis <- function(
  cfg = get_analysis_config(),
  output_dir = NULL,
  quiet = FALSE
) {
  if (!is.null(output_dir)) {
    cfg$output_dir <- output_dir
  }
  cfg$quiet <- quiet

  if (is.null(cfg$output_dir)) {
    cfg$output_dir <- file.path(tempdir(), "perf", "perf_pipeline")
  }

  start_time <- proc.time()[["elapsed"]]

  if (!quiet) {
    progressr::handlers(progressr::handler_txtprogressbar(
      style = 3L,
      width = 40L,
      clear = FALSE
    ))
    message(strrep("\u2500", 70L))
    message("  WHEP Pipeline \u2014 Performance Analysis Framework")
    message(sprintf("  stages      : %s", paste(cfg$stages, collapse = ", ")))
    message(sprintf(
      "  input_sizes : %s",
      paste(cfg$input_sizes, collapse = ", ")
    ))
    message(sprintf("  n_reps      : %d", cfg$n_reps))
    message(sprintf("  output_dir  : %s", cfg$output_dir))
    message(strrep("\u2500", 70L))
  }

  # ── run all stages ─────────────────────────────────────────────────────────
  all_results <- run_all_stages(cfg)

  # ── per-stage diagnostics ─────────────────────────────────────────────────
  stage_diagnostics <- lapply(cfg$stages, function(s) {
    diagnose_stage(s, all_results$by_stage[[s]], cfg)
  })
  names(stage_diagnostics) <- cfg$stages

  # ── print per-stage reports ───────────────────────────────────────────────
  if (!quiet) {
    for (s in cfg$stages) {
      print_stage_report(stage_diagnostics[[s]])
    }
  }

  # ── global diagnostic ─────────────────────────────────────────────────────
  global_diagnostic <- build_global_diagnostic(stage_diagnostics)

  # ── flat report (backward compat) ─────────────────────────────────────────
  if (!quiet) {
    print_global_report(global_diagnostic)
    print_complexity_report(all_results$complexity)
  }

  # ── Markdown export ───────────────────────────────────────────────────────
  resolved_preset_name <- if (!is.null(cfg$preset_name)) {
    .sanitize_perf_preset_name(cfg$preset_name, default = "custom")
  } else {
    infer_perf_preset_name(cfg, default = "custom")
  }

  markdown_paths <- export_analysis_markdown(
    results = all_results,
    output_path = cfg$output_dir,
    preset_name = resolved_preset_name
  )
  summary_filename <- get_perf_general_summary_report_filename(
    preset_name = resolved_preset_name
  )
  markdown_path <- markdown_paths[[summary_filename]]

  # ── persist full analysis object to .qs ──────────────────────────────────
  analysis_object <- c(
    all_results,
    list(
      stage_diagnostics = stage_diagnostics,
      global_diagnostic = global_diagnostic,
      cfg = cfg
    )
  )
  qs_out <- persist_analysis(analysis_object, cfg$qs_path)

  elapsed <- proc.time()[["elapsed"]] - start_time
  if (!quiet) {
    time_str <- format_elapsed_time(elapsed)
    message(sprintf("\n  Analysis complete in %s", time_str))
    message(strrep("\u2500", 70L))
  }

  analysis_object$markdown_path <- markdown_path
  analysis_object$markdown_paths <- markdown_paths
  analysis_object$qs_path <- qs_out
  return(invisible(analysis_object))
}

#' @title Run performance analysis
#' @description Convenience wrapper around run_big_o_analysis() exposing common
#'   run controls as direct arguments.
#'
#' @param input_sizes An integer vector of benchmark sizes.
#' @param n_reps An integer scalar of repetitions per size.
#' @param n_year_cols An integer scalar number of synthetic year columns.
#' @param stages An optional character vector of stage identifiers.
#' @param na_fraction A numeric scalar missing-value fraction.
#' @param dup_fraction A numeric scalar duplicate fraction.
#' @param rng_seed An integer scalar random seed.
#' @param output_dir A character scalar output directory.
#' @param preset_name An optional character scalar preset label.
#' @param quiet A logical scalar verbosity flag.
#' @return An invisible named list returned by run_big_o_analysis().
run_perf <- function(
  input_sizes = as.integer(c(1e3, 2e3, 5e3, 1e4, 2e4)),
  n_reps = 5L,
  n_year_cols = 10L,
  stages = NULL,
  na_fraction = 0.05,
  dup_fraction = 0.02,
  rng_seed = 42L,
  output_dir = here::here(
    "data",
    "3-export",
    "processed_data",
    "perf",
    "perf_pipeline"
  ),
  preset_name = NULL,
  quiet = FALSE
) {
  cfg <- get_analysis_config()
  cfg$input_sizes <- as.integer(input_sizes)
  cfg$n_reps <- as.integer(n_reps)
  cfg$n_year_cols <- as.integer(n_year_cols)
  cfg$na_fraction <- as.numeric(na_fraction)
  cfg$dup_fraction <- as.numeric(dup_fraction)
  cfg$rng_seed <- as.integer(rng_seed)
  cfg$output_dir <- output_dir

  if (!is.null(stages)) {
    cfg$stages <- as.character(stages)
  }

  if (is.null(preset_name) || length(preset_name) == 0L) {
    cfg$preset_name <- infer_perf_preset_name(cfg, default = "custom")
  } else {
    cfg$preset_name <- .sanitize_perf_preset_name(
      preset_name,
      default = "custom"
    )
  }

  if (cfg$preset_name %in% names(get_perf_run_presets())) {
    cfg$output_dir <- resolve_perf_output_dir_for_preset(
      output_dir = cfg$output_dir,
      preset_name = cfg$preset_name
    )
  }

  run_big_o_analysis(cfg = cfg, quiet = quiet)
}
