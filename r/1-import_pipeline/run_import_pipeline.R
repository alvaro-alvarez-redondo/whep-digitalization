# script: run import pipeline script
# description: discover, read, transform, and validate all import files.

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


## Build ordered list of import-stage scripts and source them
import_stage_dirs <- c(
  "10-file_io",
  "11-reading",
  "12-transform",
  "13-output"
)

# collect R scripts from each stage directory in alphabetical order
import_scripts <- unlist(
  lapply(import_stage_dirs, function(d) {
    stage_path <- here::here("r", "1-import_pipeline", d)
    files <- list.files(stage_path, pattern = "\\.R$", full.names = FALSE)
    if (length(files) == 0) return(character(0))
    files <- sort(files)
    file.path(d, files)
  }),
  use.names = FALSE
)

# fail early if any expected script is missing (helps surface refactor gaps)
missing_scripts <- import_scripts[!file.exists(here::here("r", "1-import_pipeline", import_scripts))]
if (length(missing_scripts) > 0) {
  cli::cli_abort(c("Missing import pipeline scripts:", paste0("- ", missing_scripts)))
}

# Always source the current implementations to pick up refactors and avoid
# stale function checks; source in-stage order to respect dependencies.
for (script_name in import_scripts) {
  source(here::here("r", "1-import_pipeline", script_name), echo = FALSE)
}

#' @title run import pipeline
#' @description run the complete import pipeline by discovering source files,
#' reading sheets, transforming to wide and long outputs, validating each
#' document group, and consolidating validated long tables with diagnostics.
#' audit execution is handled in the export pipeline stage.
#' @param config named list containing at least `paths$data$import$raw` as a
#' character scalar directory.
#' @return named list with `data` as consolidated long `data.table`, `wide_raw`
#' as transformed wide `data.table`, and `diagnostics` list with
#' `reading_errors`, `validation_errors`, and `warnings` character vectors.
#' @importFrom checkmate assert_list assert_string assert_directory_exists assert_names assert_character assert_data_frame
#' @importFrom progressr with_progress progressor
#' @importFrom cli cli_abort
#' @examples
#' # run_import_pipeline(config)
run_import_pipeline <- function(config) {
  checkmate::assert_list(config, any.missing = FALSE)
  checkmate::assert_string(config$paths$data$import$raw, min.chars = 1)
  checkmate::assert_directory_exists(config$paths$data$import$raw)

  cached_result <- load_pipeline_checkpoint("import_pipeline", config)
  if (!is.null(cached_result)) {
    return(cached_result)
  }

  file_list_dt <- discover_files(config$paths$data$import$raw)

  if (nrow(file_list_dt) == 0) {
    cli::cli_abort("no excel files were found. pipeline terminated")
  }

  total_steps <- (2 * nrow(file_list_dt)) + 4

  result <- progressr::with_progress({
    progress <- progressr::progressor(steps = total_steps)

    progress("Import Pipeline Progress: reading source files")
    read_pipeline_result <- read_pipeline_files(
      file_list_dt = file_list_dt,
      config = config,
      progressor = progress
    )

    checkmate::assert_names(
      names(read_pipeline_result),
      must.include = c("read_data_list", "errors")
    )
    checkmate::assert_list(
      read_pipeline_result$read_data_list,
      any.missing = TRUE
    )
    checkmate::assert_character(
      read_pipeline_result$errors,
      any.missing = FALSE
    )

    read_data_list <- read_pipeline_result$read_data_list

    progress("Import Pipeline Progress: transforming source files")
    transformed <- transform_files_list(
      file_list_dt = file_list_dt,
      read_data_list = read_data_list,
      config = config,
      progressor = progress
    )

    transformed$long_raw <- drop_na_value_rows(transformed$long_raw)

    progress("Import Pipeline Progress: splitting validation groups")
    validation_data_list <- split(
      transformed$long_raw,
      by = "document",
      keep.by = TRUE,
      sorted = FALSE
    )

    progress("Import Pipeline Progress: validating transformed records")
    validation_results <- lapply(
      validation_data_list,
      function(document_dt) validate_long_dt(document_dt, config)
    )

    audited_dt_list <- lapply(validation_results, `[[`, "data")

    validation_errors <- unlist(
      lapply(validation_results, `[[`, "errors"),
      use.names = FALSE
    )

    consolidated_result <- consolidate_audited_dt(audited_dt_list, config)
    checkmate::assert_names(
      names(consolidated_result),
      must.include = c("data", "warnings")
    )
    checkmate::assert_data_frame(consolidated_result$data, min.rows = 0)
    checkmate::assert_character(
      consolidated_result$warnings,
      any.missing = FALSE
    )

    consolidated_data <- sort_pipeline_stage_dt(consolidated_result$data)

    list(
      data = consolidated_data,
      wide_raw = transformed$wide_raw,
      diagnostics = list(
        reading_errors = read_pipeline_result$errors,
        validation_errors = validation_errors,
        warnings = consolidated_result$warnings
      )
    )
  })

  save_pipeline_checkpoint(
    result = result,
    checkpoint_name = "import_pipeline",
    config = config
  )

  return(result)
}

#' @title run import pipeline automatically
#' @description execute `run_import_pipeline()` when automatic mode is enabled
#' and a valid `config` object is available in the calling environment.
#' @param auto_run logical scalar controlling whether automatic execution should
#' occur.
#' @param env environment used to resolve and assign pipeline artifacts.
#' @return invisible named list from `run_import_pipeline()` when executed,
#' otherwise invisible `NULL`.
#' @importFrom checkmate assert_flag assert_environment
#' @importFrom cli cli_warn
#' @examples
#' run_import_pipeline_auto(auto_run = FALSE)
run_import_pipeline_auto <- function(auto_run, env = .GlobalEnv) {
  checkmate::assert_flag(auto_run)
  checkmate::assert_environment(env)

  pipeline_constants <- get_pipeline_constants()

  if (!isTRUE(auto_run)) {
    return(invisible(NULL))
  }

  if (!exists("config", envir = env, inherits = TRUE)) {
    cli::cli_warn(
      "automatic import pipeline skipped: missing {.val config} in environment"
    )
    return(invisible(NULL))
  }

  config_value <- get("config", envir = env, inherits = TRUE)
  import_pipeline_result <- run_import_pipeline(config = config_value)

  assignment_helper <- pipeline_constants$helper_requirements$assignment_helper

  if (!exists(assignment_helper, mode = "function", inherits = TRUE)) {
    cli::cli_abort(
      "missing shared helper {.fn {assignment_helper}}; source {.file {pipeline_constants$helper_requirements$assignment_helper_source}}"
    )
  }

  assignment_values <- list(
    import_pipeline_result$data,
    import_pipeline_result$wide_raw,
    import_pipeline_result$diagnostics$reading_errors,
    import_pipeline_result$diagnostics$validation_errors,
    import_pipeline_result$diagnostics$warnings
  )
  names(assignment_values) <- c(
    pipeline_constants$object_names$raw,
    pipeline_constants$object_names$wide_raw,
    pipeline_constants$object_names$collected_reading_errors,
    pipeline_constants$object_names$collected_errors,
    pipeline_constants$object_names$collected_warnings
  )

  assign_environment_values(values = assignment_values, env = env)

  return(invisible(import_pipeline_result))
}

run_import_pipeline_auto(
  auto_run = isTRUE(getOption(
    get_pipeline_constants()$auto_run_options$import,
    TRUE
  ))
)
