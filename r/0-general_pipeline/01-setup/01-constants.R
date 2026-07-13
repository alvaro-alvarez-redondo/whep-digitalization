# pipeline constants and global options
options(
  stringsAsFactors = FALSE,
  scipen = 999,
  datatable.showProgress = FALSE,
  datatable.verbose = FALSE
)

.pipeline_constants_cache <- NULL

#' Retrieve pipeline constants
#' Returns a cached named list of pipeline constants, including dataset names,
#' timestamp formats, patterns, performance settings, defaults, column
#' definitions, and export configuration.
#' @return Named list of pipeline constants.
#' @examples
#' constants <- get_pipeline_constants()
#' constants$dataset_default_name
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
      header_normalize_whitespace = "\\s+",
      header_normalize_separator_spacing = "\\s*([/-])\\s*",
      header_normalize_non_alnum = "[^a-z0-9\\-/]+",
      header_normalize_multi_underscore = "_{2,}",
      header_normalize_trim_underscore = "^_+|_+$",
      header_normalize_fast_path = "^[a-z0-9](?:[a-z0-9/_-]*[a-z0-9])?$",
      year_column = "^\\d{4}(-\\d{4})?$",
      yearbook_token_4digit = "^\\d{4}$"
    ),
    transforms = list(
      latin_ascii_lower = "Latin-ASCII; Lower"
    ),
    header_normalization = list(
      whitespace_replacement = " ",
      separator_replacement = "$1",
      non_alnum_replacement = "_",
      trim_underscore_replacement = "",
      canonical_aliases = c(
        country = "polity"
      )
    ),
    performance = list(
      normalize_unique_min_n = 256L,
      normalize_unique_sample_n = 2048L,
      normalize_unique_ratio_threshold = 0.85,
      import_workbook_batch_size = 32L,
      # Import parallelism. The auto sentinel (default) auto-enables parallel
      # reading at min(import_parallel_workers_auto_max, cores - 1) workers via
      # future::multisession (resolved by resolve_import_effective_workers());
      # output is identical to sequential. An explicit integer override (the
      # whep.import.parallel_workers option or
      # config$performance$import_parallel_workers) is always honored, with 1L =
      # sequential. Import is partly serialization/IO bound, so returns taper off:
      # a worker-count sweep (729 workbooks, 16 cores) measured seq 89.5s ->
      # 4w 42.5s -> 8w 38.3s (best) -> 12w 44.6s (regresses). 8 is the optimum;
      # output is byte-identical to sequential at every worker count. The
      # literal-count resolver resolve_import_parallel_workers() treats the
      # sentinel as 1L (sequential), so its default-sequential contract holds.
      import_parallel_workers = "auto",
      import_parallel_workers_auto_token = "auto",
      import_parallel_workers_auto_max = 8L,
      # future.apply scheduling factor for the parallel import READ stage.
      # future_lapply makes ~`factor * workers` chunks and relays progress only
      # as each chunk's future RESOLVES; the default factor of 1 makes exactly
      # `workers` chunks -> few resolution rounds -> the bar can sit still then
      # jump. A factor > 1 makes more, smaller chunks so progress relays steadily
      # across the ~tens-of-seconds read. 4 is verified perf-neutral on the full
      # dataset (the read closure captures only small `config`, so extra chunks
      # add negligible serialization). NOT applied to the transform stage: its
      # closure captures the large `read_data_list`, so more chunks there
      # re-serialize it and measured ~5x slower. Override via
      # config$performance$import_future_scheduling.
      import_future_scheduling = 4
    ),
    defaults = list(
      unknown_document = "(unknown_document)",
      unknown_commodity = "(unknown_commodity)",
      list_blank_label = "(blank)"
    ),
    sorting = list(
      stage_row_order = c(
        "hemisphere",
        "continent",
        "polity",
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
    progress_dark = "whep.progress.dark",
    checkpointing_enabled = "whep.checkpointing.enabled",
    import_parallel_workers = "whep.import.parallel_workers"
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

  constants$general_pipeline <- list(
    total_steps = 5L,
    progress_messages = list(
      source_scripts = "sourcing general scripts",
      check_dependencies = "checking dependencies",
      load_dependencies = "loading dependencies",
      load_config = "loading pipeline configuration",
      create_dirs = "creating required directories"
    )
  )

  # Unified progress-bar presentation, shared by all four stage runners.
  #
  # Every stage opens its own progressr::with_progress() block and builds a
  # cli-backed handler via pipeline_progress_handlers(stage). The handler shows
  # a spinner + bar + percent + ETA + the live per-step status message, so the
  # bar reflects REAL progress and animates instead of freezing. The format
  # string itself is assembled in pipeline_progress_handlers() from these
  # pieces: each stage is distinguished only by its label (baked as a string
  # literal because progressr's progressor() has no name= arg -> {cli::pb_name}
  # would render empty), the import stage adds a throughput column (rate_stages),
  # and the colors come from the theme-aware `palette` below.
  #
  # palette: each role is a cli call (function name + optional arg) spliced into
  # the format as `{cli::<value>(<token>)}` by pipeline_progress_handlers(). The
  # palette is chosen by pipeline_progress_dark() (RStudio dark theme / the
  # whep.progress.dark option / default dark). Fixed ANSI shades like col_silver
  # read fine on a light background but turn muddy on a dark one, so the dark
  # palette uses white + soft pastel truecolor (via make_ansi_style) for legible,
  # calm accents on a dark console.
  #   muted   - spinner, counts, rate, elapsed, status
  #   accent  - the bold stage name AND the percent (one unified color)
  #   success - the done tick + the word "done"
  #
  # No format_failed: progressr does not render a custom failure format on a
  # thrown condition (it prints its own "interrupted" notice), so failures are
  # surfaced via cli::cli_abort at the call sites instead.
  constants$progress <- list(
    show_after = 0,
    # Minimum seconds between bar redraws. The parallel import relays progress in
    # bursts (a whole batch's per-file ticks arrive at once when its future
    # resolves); with no throttle the cli bar repaints dozens of times in a few
    # milliseconds, which reads as flicker (the bar appears to vanish and
    # reappear). Throttling coalesces each burst into a single repaint.
    update_interval = 0.2,
    stage_labels = list(
      general = "general",
      import = "import",
      postpro = "post-process",
      export = "export"
    ),
    palette = list(
      light = list(
        muted = "col_silver",
        accent = "col_cyan",
        success = "col_green"
      ),
      dark = list(
        muted = "col_br_white",
        accent = "make_ansi_style('#a6c8ff')",
        success = "make_ansi_style('#a6e3a1')"
      )
    ),
    # Stages whose in-progress line includes the throughput-rate column.
    rate_stages = "import",
    # Fallback when cli / progressr::handler_cli is unavailable.
    fallback_bar_width = 40L,
    # sprintf template for the postpro per-pass pulse (stage name, pass index).
    pulse_template = "%s pass %d",
    # Per-step status messages (the live text shown as {cli::pb_status}).
    messages = list(
      import = list(
        reading = "reading source files",
        read_file = "reading %s",
        transforming = "transforming source files",
        transform_file = "transforming %s",
        splitting = "splitting validation groups",
        validating = "validating transformed records"
      ),
      postpro = list(
        audit = "auditing raw data",
        init_dirs = "initializing audit directories",
        templates = "generating rule templates",
        collect_preflight = "collecting preflight checks",
        assert_preflight = "asserting preflight checks",
        clean = "running clean layer",
        standardize = "running standardize layer",
        harmonize = "running harmonize layer",
        persist = "persisting diagnostics"
      ),
      export = list(
        processed = "processed workbooks",
        lists = "lists workbooks"
      )
    )
  )

  columns <- list(
    base = c("continent", "polity", "unit", "footnotes"),
    id = c(
      "commodity",
      "variable",
      "unit",
      "hemisphere",
      "continent",
      "polity",
      "footnotes"
    ),
    value = c("year", "value"),
    system = c("notes", "yearbook", "document")
  )

  fixed_export_columns <- c(
    "hemisphere",
    "continent",
    "polity",
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
    "polity",
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
