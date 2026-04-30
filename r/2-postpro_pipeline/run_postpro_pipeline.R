# script: run post-processing pipeline
# description: source post-processing scripts and execute deterministic clean and
# harmonize stages with structured audit persistence.

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


#' @title Source one post-processing script
#' @description Sources a single script with deterministic error handling.
#' @param script_path Character scalar script path.
#' @return Invisibly returns `TRUE`.
#' @importFrom checkmate assert_string
source_postpro_script <- function(script_path) {
  checkmate::assert_string(script_path, min.chars = 1)

  if (!file.exists(script_path)) {
    cli::cli_abort(
      "Required post-processing script not found: {.path {script_path}}"
    )
  }

  tryCatch(
    {
      source(script_path, local = FALSE, echo = FALSE)
      return(invisible(TRUE))
    },
    error = function(error_condition) {
      cli::cli_abort(c(
        "Failed while sourcing post-processing script.",
        "x" = "script: {.path {script_path}}",
        "x" = "details: {error_condition$message}"
      ))
    }
  )
}

#' @title Source post-processing scripts in deterministic order
#' @description Sources post-processing scripts discovered by stage directories.
#' @param pipeline_root Character scalar path to post-processing script folder.
#' @return Invisibly returns `TRUE`.
#' @importFrom checkmate assert_string
source_postpro_scripts <- function(
  pipeline_root = here::here("r", "2-postpro_pipeline")
) {
  checkmate::assert_string(pipeline_root, min.chars = 1)

  # Keep explicit stage order deterministic while discovering scripts
  stage_dirs <- c(
    "20-data_audit",
    "21-postpro_utilities",
    "23-postpro_rule_engine",
    "22-clean_harmonize_data",
    "24-standardize_units",
    "25-postpro_diagnostics"
  )

  # build full script paths using here::here for consistency
  script_paths <- unlist(
    lapply(stage_dirs, function(stage_dir) {
      stage_path <- here::here("r", "2-postpro_pipeline", stage_dir)
      files <- list.files(stage_path, pattern = "\\.R$", full.names = FALSE)
      if (length(files) == 0L) return(character(0))
      files <- sort(files)
      vapply(files, function(f) here::here("r", "2-postpro_pipeline", stage_dir, f), character(1))
    }),
    use.names = FALSE
  )

  missing_scripts <- script_paths[!file.exists(script_paths)]
  if (length(missing_scripts) > 0L) {
    cli::cli_abort(c("Missing post-processing scripts:", paste0("- ", missing_scripts)))
  }

  purrr::walk(script_paths, function(p) source_postpro_script(p))

  return(invisible(TRUE))
}

#' @title Run units standardization stage
#' @description Executes units standardization using the clean dataset and
#' pipeline configuration.
#' @param clean_dt clean dataset to standardize.
#' @param config Named configuration list.
#' @return Standardized dataset returned by `run_standardize_units_layer_batch`.
#' @importFrom checkmate assert_data_frame assert_list
run_units_standardization_stage <- function(clean_dt, config) {
  checkmate::assert_data_frame(clean_dt, min.rows = 0)
  checkmate::assert_list(config, min.len = 1)

  return(run_standardize_units_layer_batch(
    clean_dt = clean_dt,
    config = config
  ))
}

#' @title Get required object from environment or return `NULL`
#' @description Retrieves an object when present; otherwise warns and returns
#' `NULL` for deterministic auto-run short-circuit behavior.
#' @param object_name Character scalar object name.
#' @param env Environment to query.
#' @return Object value or `NULL`.
#' @importFrom checkmate assert_string assert_environment
get_required_object_or_null <- function(object_name, env) {
  checkmate::assert_string(object_name, min.chars = 1)
  checkmate::assert_environment(env)

  if (!exists(object_name, envir = env, inherits = TRUE)) {
    cli::cli_warn(
      "Automatic post-processing pipeline skipped: missing {.val {object_name}} in environment."
    )

    return(NULL)
  }

  return(get(object_name, envir = env, inherits = TRUE))
}

#' @title Run post-processing pipeline batch
#' @description Runs deterministic preflight, clean stage, units standardization stage,
#' harmonize stage, and persistence of dataset and audit artifacts.
#' @param raw_dt Raw dataset.
#' @param config Named configuration list.
#' @param dataset_name Character scalar dataset identifier.
#' @return Post-processed `data.table` with `pipeline_diagnostics` attribute.
#' @importFrom checkmate assert_data_frame assert_list assert_string
#' @importFrom progressr with_progress progressor
run_postpro_pipeline_batch <- function(
  raw_dt,
  config,
  dataset_name = get_pipeline_constants()$dataset_default_name
) {
  checkmate::assert_data_frame(raw_dt, min.rows = 0)
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(dataset_name, min.chars = 1)

  source_postpro_scripts()

  total_steps <- 9

  return(progressr::with_progress({
    progress <- progressr::progressor(steps = total_steps)

    progress("Post-Processing Pipeline Progress: auditing raw data")
    audited_raw_dt <- audit_data_output(
      dataset_dt = raw_dt,
      config = config
    )

    progress(
      "Post-Processing Pipeline Progress: initializing audit directories"
    )
    audit_paths <- initialize_postpro_output_root(config)

    progress("Post-Processing Pipeline Progress: generating rule templates")
    template_paths <- generate_postpro_rule_templates(
      config = config,
      overwrite = TRUE
    )

    progress("Post-Processing Pipeline Progress: collecting preflight checks")
    preflight_result <- collect_postpro_preflight(
      config = config,
      dataset_columns = colnames(audited_raw_dt),
      expected_columns = colnames(audited_raw_dt)
    )

    progress("Post-Processing Pipeline Progress: asserting preflight checks")
    assert_postpro_preflight(preflight_result)

    progress("Post-Processing Pipeline Progress: running clean layer")
    clean_dt <- run_cleaning_layer_batch(
      dataset_dt = audited_raw_dt,
      config = config,
      dataset_name = dataset_name
    )
    clean_dt <- sort_pipeline_stage_dt(clean_dt)

    progress("Post-Processing Pipeline Progress: running standardize layer")
    normalize_dt <- run_units_standardization_stage(
      clean_dt = clean_dt,
      config = config
    )
    normalize_dt <- sort_pipeline_stage_dt(normalize_dt)

    progress("Post-Processing Pipeline Progress: running harmonize layer")
    harmonize_dt <- run_harmonize_layer_batch(
      dataset_dt = normalize_dt,
      config = config,
      dataset_name = dataset_name
    )
    harmonize_dt <- sort_pipeline_stage_dt(harmonize_dt)

    clean_audit <- attr(clean_dt, "layer_audit")
    standardize_audit <- attr(normalize_dt, "layer_audit")
    standardize_rules <- attr(normalize_dt, "layer_rules")
    standardize_matched_rule_counts <- attr(
      normalize_dt,
      "layer_matched_rule_counts"
    )
    harmonize_audit <- attr(harmonize_dt, "layer_audit")
    harmonize_overwrite_events <- attr(
      harmonize_dt,
      "layer_last_rule_wins_overwrites"
    )

    if (!is.data.frame(standardize_rules)) {
      standardize_rules <- data.table::data.table()
    }

    if (!is.data.frame(standardize_matched_rule_counts)) {
      standardize_matched_rule_counts <- data.table::data.table()
    }

    progress("Post-Processing Pipeline Progress: persisting diagnostics")
    audit_output_path <- persist_postpro_audit(
      clean_audit_dt = clean_audit,
      harmonize_audit_dt = harmonize_audit,
      standardize_audit_dt = standardize_audit,
      standardize_rules_dt = standardize_rules,
      standardize_matched_rule_counts_dt = standardize_matched_rule_counts,
      final_stage_dt = harmonize_dt,
      last_rule_wins_overwrites_dt = harmonize_overwrite_events,
      config = config
    )

    diagnostics <- list(
      clean = attr(clean_dt, "layer_diagnostics"),
      standardize_units = attr(normalize_dt, "layer_diagnostics"),
      harmonize = attr(harmonize_dt, "layer_diagnostics"),
      outputs = list(
        audit_output_path = audit_output_path,
        audit_root_dir = audit_paths$audit_root_dir,
        diagnostics_dir = audit_paths$diagnostics_dir,
        templates_dir = audit_paths$templates_dir,
        audit_dir = audit_paths$audit_dir,
        runtime_cache_dir = audit_paths$runtime_cache_dir,
        clean_harmonize_template_path = template_paths[[
          "clean_harmonize_template"
        ]],
        data_audit_output_path = config$paths$data$audit$audit_file_path
      )
    )

    attr(harmonize_dt, "pipeline_diagnostics") <- diagnostics
    attr(harmonize_dt, "stage_clean") <- clean_dt
    attr(harmonize_dt, "stage_normalize") <- normalize_dt

    return(harmonize_dt)
  }))
}

#' @title Run post-processing pipeline automatically
#' @description Runs post-processing when enabled and required objects exist.
#' @param auto_run Logical scalar auto-run flag.
#' @param env Environment for object resolution and assignment.
#' @return Invisibly returns post-processed dataset or `NULL`.
#' @importFrom checkmate assert_flag assert_environment
run_postpro_pipeline_auto <- function(auto_run, env = .GlobalEnv) {
  checkmate::assert_flag(auto_run)
  checkmate::assert_environment(env)

  pipeline_constants <- get_pipeline_constants()

  if (!isTRUE(auto_run)) {
    return(invisible(NULL))
  }

  raw_value <- get_required_object_or_null(
    pipeline_constants$object_names$raw,
    env
  )
  config_value <- get_required_object_or_null("config", env)

  if (is.null(raw_value) || is.null(config_value)) {
    return(invisible(NULL))
  }

  harmonize_dt <- run_postpro_pipeline_batch(
    raw_dt = raw_value,
    config = config_value,
    dataset_name = pipeline_constants$dataset_default_name
  )

  assignment_helper <- pipeline_constants$helper_requirements$assignment_helper

  if (!exists(assignment_helper, mode = "function", inherits = TRUE)) {
    cli::cli_abort(
      "missing shared helper {.fn {assignment_helper}}; source {.file {pipeline_constants$helper_requirements$assignment_helper_source}}"
    )
  }

  assignment_values <- list(
    attr(harmonize_dt, "stage_clean"),
    attr(harmonize_dt, "stage_normalize"),
    harmonize_dt
  )
  names(assignment_values) <- c(
    pipeline_constants$object_names$clean,
    pipeline_constants$object_names$normalize,
    pipeline_constants$object_names$harmonize
  )

  assign_environment_values(values = assignment_values, env = env)

  return(invisible(harmonize_dt))
}

run_postpro_pipeline_auto(
  auto_run = isTRUE(getOption(
    get_pipeline_constants()$auto_run_options$postpro,
    TRUE
  ))
)
