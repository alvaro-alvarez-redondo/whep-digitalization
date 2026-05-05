if (!exists("get_pipeline_constants", mode = "function", inherits = TRUE)) {
  source(
    here::here("r", "0-general_pipeline", "01-setup", "01-constants.R"),
    echo = FALSE
  )
  source(
    here::here("r", "0-general_pipeline", "01-setup", "01-config.R"),
    echo = FALSE
  )
  source(
    here::here("r", "0-general_pipeline", "01-setup", "01-directories.R"),
    echo = FALSE
  )
}

#' @title Run full project pipeline
#' @description Runs the general, import, post-processing, and export pipeline
#'   scripts in deterministic sequence.
#'
#' @param show_view Logical scalar. If `TRUE`, display `whep_data_raw` in the
#'   RStudio viewer when the object exists.
#' @param pipeline_root Character scalar. Root folder containing pipeline
#'   scripts.
#'
#' @return Invisibly returns `TRUE` when all pipeline scripts execute
#'   successfully.
#' @importFrom checkmate assert_flag assert_string assert_directory_exists assert_character
#' @importFrom cli cli_abort cli_alert_info
#' @importFrom purrr walk
#'
#' @examples
#' \dontrun{
#' run_pipeline(show_view = FALSE)
#' }
#' @export
run_pipeline <- function(
  show_view = interactive(),
  pipeline_root = here::here("r")
) {
  pipeline_start_time <- proc.time()

  assert_pipeline_runtime_dependencies()

  checkmate::assert_flag(show_view)
  checkmate::assert_string(pipeline_root, na.ok = FALSE, min.chars = 1)

  normalize_pipeline_root <- normalizePath(
    path = pipeline_root,
    winslash = "/",
    mustWork = FALSE
  )

  if (!dir.exists(normalize_pipeline_root)) {
    cli::cli_abort(
      "pipeline root does not exist: {.path {normalize_pipeline_root}}"
    )
  }

  pipeline_files <- resolve_pipeline_files(
    pipeline_root = normalize_pipeline_root
  )

  purrr::walk(pipeline_files, run_pipeline_script)

  maybe_view_pipeline_output(show_view = show_view)

  elapsed_seconds <- (proc.time() - pipeline_start_time)[["elapsed"]]
  iteration_summary <- build_postpro_iteration_summary()
  cli::cli_alert_success(
    paste0(
      "Pipeline completed in {.strong {format_elapsed_time(elapsed_seconds)}}",
      iteration_summary
    )
  )

  return(invisible(TRUE))
}

#' @title Build post-processing iteration summary suffix
#' @description Builds deterministic clean/harmonize loop count suffix for the
#'   pipeline completion message from post-processing diagnostics.
#' @param env Environment used to resolve pipeline output objects.
#' @return Character scalar summary suffix.
#' @keywords internal
build_postpro_iteration_summary <- function(env = .GlobalEnv) {
  checkmate::assert_environment(env)

  loop_counts <- get_postpro_iteration_loop_counts(env = env)

  paste0(
    " | cleans: ",
    format_postpro_iteration_count(loop_counts$clean),
    " | harmonizatios: ",
    format_postpro_iteration_count(loop_counts$harmonize)
  )
}

#' @title Format post-processing iteration count
#' @description Formats integer loop counts for user-facing completion
#'   messaging.
#' @param count Integer scalar loop count.
#' @return Character scalar formatted loop count.
#' @keywords internal
format_postpro_iteration_count <- function(count) {
  count_value <- suppressWarnings(as.integer(count[[1L]]))

  if (length(count_value) == 0L || is.na(count_value)) {
    return("N/A")
  }

  as.character(count_value)
}

#' @title Get post-processing iteration loop counts
#' @description Extracts clean and harmonize pass counts from the
#'   `pipeline_diagnostics` attribute attached to the harmonize dataset.
#' @param env Environment used to resolve pipeline output objects.
#' @return Named list with integer scalars `clean` and `harmonize`.
#' @keywords internal
get_postpro_iteration_loop_counts <- function(env = .GlobalEnv) {
  checkmate::assert_environment(env)

  pipeline_constants <- get_pipeline_constants()
  harmonize_name <- pipeline_constants$object_names$harmonize

  if (!exists(harmonize_name, envir = env, inherits = TRUE)) {
    return(list(clean = NA_integer_, harmonize = NA_integer_))
  }

  harmonize_dt <- get(harmonize_name, envir = env, inherits = TRUE)
  pipeline_diagnostics <- attr(harmonize_dt, "pipeline_diagnostics")

  if (!is.list(pipeline_diagnostics)) {
    return(list(clean = NA_integer_, harmonize = NA_integer_))
  }

  list(
    clean = extract_postpro_stage_pass_count(
      pipeline_diagnostics$clean
    ),
    harmonize = extract_postpro_stage_pass_count(
      pipeline_diagnostics$harmonize
    )
  )
}

#' @title Extract post-processing stage pass count
#' @description Safely extracts multi-pass `passes_executed` value from one
#'   stage diagnostics payload.
#' @param stage_diagnostics Stage diagnostics list.
#' @return Integer scalar pass count or `NA_integer_`.
#' @keywords internal
extract_postpro_stage_pass_count <- function(stage_diagnostics) {
  if (!is.list(stage_diagnostics) || !is.list(stage_diagnostics$multi_pass)) {
    return(NA_integer_)
  }

  passes <- suppressWarnings(as.integer(
    stage_diagnostics$multi_pass$passes_executed[[1L]]
  ))

  if (length(passes) == 0L || is.na(passes)) {
    return(NA_integer_)
  }

  passes
}

#' @title Assert runtime package dependencies for pipeline orchestration
#' @description Validates availability of required namespaces used by
#'   `run_pipeline()` without attaching packages to the search path.
#' @return Invisibly returns `TRUE` when all namespaces are available.
#' @keywords internal
assert_pipeline_runtime_dependencies <- function() {
  required_namespaces <- c("checkmate", "cli", "here", "purrr")

  missing_namespaces <- required_namespaces[
    !vapply(required_namespaces, requireNamespace, logical(1), quietly = TRUE)
  ]

  if (length(missing_namespaces) > 0L) {
    cli::cli_abort(
      c(
        "missing required pipeline dependencies.",
        "x" = "install missing package(s): {.val {missing_namespaces}}"
      )
    )
  }

  return(invisible(TRUE))
}

#' @title Resolve pipeline script paths
#' @description Builds ordered script paths for all pipeline stages.
#' @param pipeline_root Character scalar existing directory.
#' @return Character vector of script paths in execution order.
#' @keywords internal
resolve_pipeline_files <- function(pipeline_root) {
  checkmate::assert_string(pipeline_root, na.ok = FALSE, min.chars = 1)
  checkmate::assert_directory_exists(pipeline_root)

  pipeline_constants <- get_pipeline_constants()
  stage_runner_names <- pipeline_constants$script_names$pipeline_stage_runners

  checkmate::assert_character(
    stage_runner_names,
    min.len = 4,
    max.len = 4,
    any.missing = FALSE
  )

  stage_directories <- c(
    "0-general_pipeline",
    "1-import_pipeline",
    "2-postpro_pipeline",
    "3-export_pipeline"
  )

  pipeline_files <- file.path(
    pipeline_root,
    stage_directories,
    stage_runner_names
  )

  return(pipeline_files)
}

#' @title Source an individual pipeline script
#' @description Validates path existence, logs script execution, and sources the
#'   script.
#' @param pipeline_file Character scalar path to pipeline script.
#' @return Invisibly returns `TRUE`.
#' @keywords internal
run_pipeline_script <- function(pipeline_file) {
  checkmate::assert_string(pipeline_file, na.ok = FALSE, min.chars = 1)

  if (!file.exists(pipeline_file)) {
    cli::cli_abort(
      "{.strong required pipeline script is missing: {.path {pipeline_file}}}"
    )
  }

  pipeline_name <- basename(pipeline_file)
  cli::cli_alert_info(
    "{.strong running pipeline script: {.val {pipeline_name}}}"
  )

  tryCatch(
    {
      source(pipeline_file, local = FALSE, echo = FALSE)
      return(invisible(TRUE))
    },
    error = function(error_condition) {
      cli::cli_abort(c(
        "pipeline script execution failed.",
        "x" = "script: {.path {pipeline_file}}",
        "x" = "details: {error_condition$message}"
      ))
    }
  )
}

#' @title Optionally view pipeline output object
#' @description Opens the most advanced available pipeline dataset in RStudio viewer if requested.
#' @param show_view Logical scalar controlling view behavior.
#' @return Invisibly returns `TRUE`.
#' @keywords internal
maybe_view_pipeline_output <- function(show_view) {
  checkmate::assert_flag(show_view)

  if (show_view) {
    pipeline_constants <- get_pipeline_constants()
    object_priority <- c(
      pipeline_constants$object_names$harmonize,
      pipeline_constants$object_names$normalize,
      pipeline_constants$object_names$clean,
      pipeline_constants$object_names$raw
    )

    available_objects <- object_priority[vapply(
      object_priority,
      exists,
      logical(1),
      inherits = TRUE
    )]

    available_object <- if (length(available_objects) > 0L) {
      available_objects[[1L]]
    } else {
      NA_character_
    }

    if (!is.na(available_object) && nzchar(available_object)) {
      utils::View(get(available_object, inherits = TRUE))
    }
  }

  return(invisible(TRUE))
}

if (
  isTRUE(getOption(get_pipeline_constants()$auto_run_options$pipeline, TRUE))
) {
  run_pipeline()
}
