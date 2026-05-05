# script: pipeline configuration
# description: builds deterministic configuration objects for pipeline execution.

#' @title load pipeline config
#' @description builds and returns a deterministic configuration object for the
#' pipeline, including project-root-relative paths, file names, semantic column
#' groups, export settings, default values, and dataset-specific audit paths.
#' audit paths are generated dynamically from `dataset_name` so the auditing
#' workflow is reusable across multiple datasets.
#' @param dataset_name character scalar dataset identifier used to build
#' audit directories and audit workbook names with the
#' `{dataset_name}_data_validation_audit.xlsx` convention. when `null` or empty,
#' the function
#' attempts to derive a name from `data` attributes in `...` and falls back to
#' `whep_data_raw`.
#' @param ... optional values. if a named argument `data` is provided and has a
#' `dataset_name` attribute, it is used as a fallback source for dataset naming.
#' @return named list with `project_root`, `dataset_name`, `paths`, `files`,
#' `columns`, `column_required`, `column_id`, `column_order`, `export_config`,
#' `defaults`, and `messages`. `export_config$styles$error_highlight` defines
#' centralized workbook styling for invalid audit cells. `paths$data$audit` contains
#' `audit_root_dir`, `audit_dir`, `diagnostics_dir`,
#' `templates_dir`, `runtime_cache_dir`, `audit_file_name`, and `audit_file_path`
#' for easy direct access.
#' @importFrom here here
#' @importFrom fs dir_create path
#' @importFrom checkmate assert_string assert_directory_exists
#' @importFrom cli cli_abort
#' @importFrom purrr walk
#' @examples
#' config <- load_pipeline_config("whep_data_raw")
#' names(config)
load_pipeline_config <- function(
  dataset_name = get_pipeline_constants()$dataset_default_name,
  ...
) {
  constants <- get_pipeline_constants()
  config_defaults <- constants$config_defaults
  path_cfg <- constants$paths

  optional_args <- list(...)

  inferred_dataset_name <- NULL

  if (!is.null(optional_args$data)) {
    inferred_dataset_name <- attr(
      optional_args$data,
      "dataset_name",
      exact = TRUE
    )

    if (is.null(inferred_dataset_name) && !is.null(names(optional_args$data))) {
      inferred_dataset_name <- attr(optional_args$data, "name", exact = TRUE)
    }
  }

  resolved_dataset_name <- dataset_name

  if (
    is.null(resolved_dataset_name) ||
      !nzchar(trimws(as.character(resolved_dataset_name)))
  ) {
    resolved_dataset_name <- inferred_dataset_name
  }

  if (
    is.null(resolved_dataset_name) ||
      !nzchar(trimws(as.character(resolved_dataset_name)))
  ) {
    resolved_dataset_name <- constants$dataset_default_name
  }

  checkmate::assert_string(resolved_dataset_name, min.chars = 1)

  normalize_dataset_name <- resolved_dataset_name |>
    as.character() |>
    tolower() |>
    iconv(from = "", to = "ascii//translit")

  normalize_dataset_name <- gsub("[^a-z0-9 ]", " ", normalize_dataset_name)
  normalize_dataset_name <- gsub("\\s+", "_", trimws(normalize_dataset_name))

  if (is.na(normalize_dataset_name) || normalize_dataset_name == "") {
    cli::cli_abort(
      "{.arg dataset_name} must resolve to a non-empty normalize value"
    )
  }

  project_root <- here::here()
  checkmate::assert_string(project_root, min.chars = 1)

  build_path <- function(...) {
    return(fs::path(project_root, ...))
  }

  raw_import_dir <- build_path(
    path_cfg$data_dir,
    path_cfg$import_dir,
    path_cfg$import_raw_dir
  )
  audit_root_dir <- build_path(path_cfg$data_dir, path_cfg$postpro_dir)
  audit_dir <- fs::path(
    audit_root_dir,
    constants$postpro$audit_dir_name
  )
  diagnostics_dir <- fs::path(
    audit_root_dir,
    constants$postpro$diagnostics_dir_name
  )
  templates_dir <- fs::path(
    audit_root_dir,
    constants$postpro$templates_dir_name
  )
  runtime_cache_dir <- fs::path(
    audit_root_dir,
    constants$postpro$runtime_cache_dir_name
  )
  audit_file_name <- paste0(
    normalize_dataset_name,
    constants$postpro$data_validation_audit_suffix
  )

  paths <- list(
    data = list(
      import = list(
        raw = raw_import_dir,
        cleaning = build_path(
          path_cfg$data_dir,
          path_cfg$import_dir,
          path_cfg$import_clean_dir
        ),
        standardization = build_path(
          path_cfg$data_dir,
          path_cfg$import_dir,
          path_cfg$import_standardize_dir
        ),
        harmonization = build_path(
          path_cfg$data_dir,
          path_cfg$import_dir,
          path_cfg$import_harmonize_dir
        )
      ),
      export = list(
        lists = build_path(
          path_cfg$data_dir,
          path_cfg$export_dir,
          path_cfg$export_lists_dir
        ),
        processed = build_path(
          path_cfg$data_dir,
          path_cfg$export_dir,
          path_cfg$export_processed_dir
        )
      ),
      audit = list(
        audit_root_dir = audit_root_dir,
        audit_dir = audit_dir,
        diagnostics_dir = diagnostics_dir,
        templates_dir = templates_dir,
        runtime_cache_dir = runtime_cache_dir,
        dataset_dir = audit_dir,
        audit_file_name = audit_file_name,
        audit_file_path = fs::path(audit_dir, audit_file_name)
      )
    )
  )

  files <- config_defaults$files
  columns <- config_defaults$columns
  column_order <- config_defaults$column_order
  fixed_export_columns <- config_defaults$fixed_export_columns
  audit_columns <- config_defaults$audit_columns
  export_config <- config_defaults$export_config

  config <- list(
    project_root = project_root,
    dataset_name = normalize_dataset_name,
    paths = paths,
    files = files,
    columns = columns,
    column_required = columns$base,
    column_id = columns$id,
    column_order = column_order,
    export_config = export_config,
    audit_columns = audit_columns,
    performance = constants$performance,
    postpro = list(
      rule_match_normalization = constants$postpro$rule_match_normalization,
      rule_match_wildcard_token = constants$postpro$rule_match_wildcard_token,
      target_update_strategies = constants$postpro$target_update_strategies,
      target_update_fast_path = constants$postpro$target_update_fast_path,
      multi_pass = constants$postpro$multi_pass,
      runtime_cache = constants$postpro$runtime_cache,
      schema_validation_cache = constants$postpro$schema_validation_cache
    ),
    sorting = constants$sorting,
    defaults = config_defaults$defaults,
    messages = config_defaults$messages
  )

  return(config)
}
