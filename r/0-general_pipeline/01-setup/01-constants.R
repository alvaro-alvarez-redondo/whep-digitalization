# pipeline constants and global options
options(
  stringsAsFactors = FALSE,
  scipen = 999,
  datatable.showProgress = FALSE,
  datatable.verbose = FALSE
)

.pipeline_constants_cache <- NULL

get_pipeline_constants <- function() {
  if (!is.null(.pipeline_constants_cache)) {
    return(.pipeline_constants_cache)
  }

  constants <- list(
    dataset_default_name = "whep_data_raw",
    timestamp_format_utc = "%Y-%m-%dT%H:%M:%SZ",
    na_placeholder = "..NA_INTERNAL..",
    na_match_key = "..NA_MATCH_KEY..",
    auto_run_options = list(
      pipeline = "whep.run_pipeline.auto",
      general = "whep.run_general_pipeline.auto",
      import = "whep.run_import_pipeline.auto",
      postpro = "whep.run_postpro_pipeline.auto",
      export = "whep.run_export_pipeline.auto"
    ),
    toggle_options = list(
      drop_na_values = "whep.drop_na_values"
    ),
    patterns = list(
      normalize_non_alnum = "[^a-z0-9]+",
      normalize_already_clean = "^([a-z0-9]+( [a-z0-9]+)*)?$",
      year_column = "^\\d{4}(-\\d{4})?$",
      yearbook_token_4digit = "^\\d{4}$"
    ),
    performance = list(
      normalize_unique_min_n = 256L,
      normalize_unique_sample_n = 2048L,
      normalize_unique_ratio_threshold = 0.85,
      import_workbook_batch_size = 32L
    ),
    defaults = list(
      unknown_document = "unknown_document",
      list_blank_label = "(blank)"
    ),
    sorting = list(
      stage_row_order = c(
        "hemisphere",
        "continent",
        "country",
        "commodity",
        "variable",
        "unit",
        "year",
        "value",
        "notes",
        "footnotes",
        "yearbook",
        "document"
      )
    ),
    script_names = list(
      general = c(
        "00-dependencies/00-validation.R",
        "00-dependencies/00-install.R",
        "00-dependencies/00-load.R",
        "00-dependencies/00-audit.R",
        "01-setup/01-constants.R",
        "01-setup/01-config.R",
        "01-setup/01-directories.R",
        "02-helpers/02-assertions.R",
        "02-helpers/02-time-formatting.R",
        "02-helpers/02-string-normalization.R",
        "02-helpers/02-numeric-coercion.R",
        "02-helpers/02-token-extraction.R",
        "02-helpers/02-data-table.R",
        "02-helpers/02-export-validation.R",
        "02-helpers/02-config-accessors.R",
        "02-helpers/02-progress.R",
        "02-helpers/02-sorting.R",
        "02-helpers/02-environment.R",
        "02-helpers/02-checkpoints.R",
        "02-helpers/02-data-cleaning.R",
        "02-helpers/02-io-cache.R"
      ),
      pipeline_stage_runners = c(
        "run_general_pipeline.R",
        "run_import_pipeline.R",
        "run_postpro_pipeline.R",
        "run_export_pipeline.R"
      )
    ),
    object_names = list(
      raw = "whep_data_raw",
      wide_raw = "whep_data_wide_raw",
      clean = "whep_data_clean",
      normalize = "whep_data_normalize",
      harmonize = "whep_data_harmonize",
      export_paths = "export_paths",
      collected_reading_errors = "collected_reading_errors",
      collected_errors = "collected_errors",
      collected_warnings = "collected_warnings"
    ),
    helper_requirements = list(
      assignment_helper = "assign_environment_values",
      assignment_helper_source = "scripts/0-general_pipeline/02-helpers/02-environment.R"
    ),
    postpro = list(
      audit_dir_name = "audit",
      diagnostics_dir_name = "diagnostics",
      templates_dir_name = "templates",
      runtime_cache_dir_name = "runtime_cache",
      clean_harmonize_template_file_name = "clean_harmonize_template.xlsx",
      standardize_units_template_file_name = "standardize_units_template.xlsx",
      data_validation_audit_suffix = "_data_validation_audit.xlsx",
      clean_audit_file_name = "clean_audit.xlsx",
      harmonize_audit_file_name = "harmonize_audit.xlsx",
      standardize_audit_file_name = "standardize_audit.xlsx",
      last_rule_wins_overwrites_file_name = "postpro_last_rule_wins_overwrites.xlsx",
      standardization = list(
        excluded_sheet_names = c("master_unit")
      ),
      rule_match_normalization = list(
        apply_once_before_stage = TRUE,
        apply_each_pass = FALSE,
        excluded_columns = c("year", "value", "yearbook", "document")
      ),
      rule_match_wildcard_token = "__ANY__",
      target_update_strategies = list(
        default = "last_rule_wins",
        concatenate_delimiter = "; ",
        by_column = c(
          notes = "concatenate"
        ),
        supported = c("last_rule_wins", "concatenate")
      ),
      target_update_fast_path = list(
        last_rule_wins_unique_row_id = TRUE
      ),
      multi_pass = list(
        enabled_by_stage = c(
          clean = TRUE,
          harmonize = TRUE
        ),
        max_passes_by_stage = c(
          clean = 10L,
          harmonize = 10L
        ),
        cycle_policy = "warn",
        supported_cycle_policies = c("warn", "abort"),
        diagnostics_verbosity = "compact",
        supported_diagnostics_verbosity = c("compact", "verbose")
      ),
      runtime_cache = list(
        enabled = FALSE,
        cache_file_name = "stage_payload_bundle_cache.rds",
        max_entries = 128L
      ),
      schema_validation_cache = list(
        enabled = FALSE,
        max_entries = 1024L
      )
    )
  )

  required_packages <- c(
    "checkmate",
    "cli",
    "data.table",
    "dplyr",
    "fs",
    "future",
    "future.apply",
    "here",
    "openxlsx",
    "progressr",
    "purrr",
    "readr",
    "readxl",
    "renv",
    "stringi",
    "stringr",
    "tibble",
    "tidyr",
    "tidyselect",
    "profvis",
    "writexl"
  )

  constants$dependencies <- list(required_packages = required_packages)

  constants$options <- list(
    progress_enabled = "whep.progress.enabled",
    checkpointing_enabled = "whep.checkpointing.enabled"
  )

  constants$patterns$footnote_non_alnum <- "[^a-z0-9 ;/*().,#%:-]+"
  constants$patterns$file_extension <- "\\.[a-z0-9]+$"
  constants$patterns$namespace_qualified <- "[A-Za-z][A-Za-z0-9.]*::"
  constants$patterns$permission_error <- "EPERM|permission denied|operation not permitted|access is denied"

  constants$time_units <- list(
    seconds_per_minute = 60L,
    seconds_per_hour = 3600L
  )

  constants$defaults$unknown_filename <- "unknown"
  constants$defaults$value_column <- "value"

  constants$paths <- list(
    data_dir = "data",
    import_dir = "1-import",
    import_raw_dir = "10-raw_import",
    import_clean_dir = "11-clean_import",
    import_standardize_dir = "12-standardize_import",
    import_harmonize_dir = "13-harmonize_import",
    postpro_dir = "2-postpro",
    export_dir = "3-export",
    export_lists_dir = "lists",
    export_processed_dir = "processed_data",
    checkpoints_dir = ".checkpoints"
  )

  constants$tokens <- list(
    commodity_start_index = 7L
  )

  constants$script_names$general_modules <- list(
    dependencies = c(
      "00-validation.R",
      "00-install.R",
      "00-load.R",
      "00-audit.R"
    ),
    setup = c(
      "01-config.R",
      "01-directories.R"
    ),
    helpers = c(
      "02-assertions.R",
      "02-time-formatting.R",
      "02-string-normalization.R",
      "02-numeric-coercion.R",
      "02-token-extraction.R",
      "02-data-table.R",
      "02-export-validation.R",
      "02-config-accessors.R",
      "02-progress.R",
      "02-sorting.R",
      "02-environment.R",
      "02-checkpoints.R",
      "02-data-cleaning.R",
      "02-io-cache.R"
    )
  )

  constants$general_pipeline <- list(
    total_steps = 5L,
    progress_bar_width = 40L,
    progress_messages = list(
      source_scripts = "general pipeline: sourcing general scripts",
      check_dependencies = "general pipeline: checking dependencies",
      load_dependencies = "general pipeline: loading dependencies",
      load_config = "general pipeline: loading pipeline configuration",
      create_dirs = "general pipeline: creating required directories"
    )
  )

  columns <- list(
    base = c("continent", "country", "unit", "footnotes"),
    id = c(
      "commodity",
      "variable",
      "unit",
      "hemisphere",
      "continent",
      "country",
      "footnotes"
    ),
    value = c("year", "value"),
    system = c("notes", "yearbook", "document")
  )

  fixed_export_columns <- c(
    "hemisphere",
    "continent",
    "country",
    "commodity",
    "variable",
    "unit",
    "notes",
    "footnotes",
    "yearbook",
    "document"
  )

  audit_columns <- c(
    "continent",
    "country",
    "commodity",
    "variable",
    "unit",
    "yearbook",
    "document"
  )

  files <- list(
    raw_data = "whep_data_raw.xlsx",
    wide_raw_data = "whep_data_wide_raw.xlsx",
    long_raw_data = "whep_data_long_raw.xlsx"
  )

  export_config <- list(
    data_suffix = ".xlsx",
    list_suffix = "_unique.xlsx",
    lists_to_export = fixed_export_columns,
    lists_workbook_name = "whep_unique_lists_raw",
    export_layers = c("harmonize"),
    styles = list(
      error_highlight = list(
        fgFill = "#FFB84D",
        fontColour = "#000000",
        textDecoration = "bold",
        border = "TopBottomLeftRight",
        borderColour = "#6D4C41",
        borderStyle = "thick"
      )
    )
  )

  constants$config_defaults <- list(
    files = files,
    columns = columns,
    column_order = constants$sorting$stage_row_order,
    fixed_export_columns = fixed_export_columns,
    audit_columns = audit_columns,
    export_config = export_config,
    defaults = list(notes_value = NA_character_),
    messages = list(show_missing_commodity_metadata_warning = FALSE)
  )

  .pipeline_constants_cache <<- constants

  return(constants)
}
