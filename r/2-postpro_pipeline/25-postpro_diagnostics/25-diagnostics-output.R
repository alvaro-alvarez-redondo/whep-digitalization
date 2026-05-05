build_postpro_diagnostics <- function(
  clean_audit_dt,
  harmonize_audit_dt,
  standardize_audit_dt
) {
  checkmate::assert_data_frame(clean_audit_dt, min.rows = 0)
  checkmate::assert_data_frame(harmonize_audit_dt, min.rows = 0)
  checkmate::assert_data_frame(standardize_audit_dt, min.rows = 0)

  clean_rule_summary <- summarize_stage_rules(clean_audit_dt, "clean")
  harmonize_rule_summary <- summarize_stage_rules(
    harmonize_audit_dt,
    "harmonize"
  )
  standardize_rule_summary <- summarize_standardize_rules(standardize_audit_dt)

  return(list(
    clean_rule_summary = clean_rule_summary,
    harmonize_rule_summary = harmonize_rule_summary,
    standardize_rule_summary = standardize_rule_summary
  ))
}

#' @title Build final-stage subset for last-rule-wins overwrites
#' @description Returns a deterministic subset of the final stage table with
#' one row per affected `row_id` where `last_rule_wins` overwrote at least one
#' prior candidate value.
#' @param final_stage_dt Final post-processing data.table/data.frame.
#' @param overwrite_events_dt Overwrite events generated during rule execution.
#' @return `data.table` with overwrite metadata and full final-stage row values.
#' @importFrom checkmate assert_data_frame
build_last_rule_wins_overwrite_subset <- function(
  final_stage_dt,
  overwrite_events_dt
) {
  checkmate::assert_data_frame(final_stage_dt, min.rows = 0)
  checkmate::assert_data_frame(overwrite_events_dt, min.rows = 0)

  final_dt <- data.table::as.data.table(data.table::copy(final_stage_dt))
  final_dt[, row_id := .I]

  metadata_empty <- data.table::data.table(
    row_id = integer(),
    overwrite_event_count = integer(),
    overwritten_columns = character(),
    overwritten_rule_files = character(),
    overwritten_stages = character()
  )

  if (nrow(final_dt) == 0L || nrow(overwrite_events_dt) == 0L) {
    return(cbind(metadata_empty, final_dt[0L, ], fill = TRUE))
  }

  events_dt <- data.table::as.data.table(data.table::copy(overwrite_events_dt))

  required_columns <- c(
    "row_id",
    "column_target",
    "rule_file_identifier",
    "execution_stage"
  )
  missing_columns <- setdiff(required_columns, names(events_dt))
  if (length(missing_columns) > 0L) {
    events_dt[, (missing_columns) := NA_character_]
  }

  events_dt[, row_id := suppressWarnings(as.integer(row_id))]
  events_dt <- events_dt[
    !is.na(row_id) & row_id >= 1L & row_id <= nrow(final_dt)
  ]

  if (nrow(events_dt) == 0L) {
    return(cbind(metadata_empty, final_dt[0L, ], fill = TRUE))
  }

  collapse_values <- function(values) {
    values_chr <- trimws(as.character(values))
    values_chr <- values_chr[!is.na(values_chr) & nzchar(values_chr)]

    if (length(values_chr) == 0L) {
      return(NA_character_)
    }

    return(paste(sort(unique(values_chr)), collapse = "; "))
  }

  row_summary <- events_dt[,
    .(
      overwrite_event_count = .N,
      overwritten_columns = collapse_values(column_target),
      overwritten_rule_files = collapse_values(rule_file_identifier),
      overwritten_stages = collapse_values(execution_stage)
    ),
    by = row_id
  ]

  row_subset <- final_dt[row_id %in% row_summary$row_id]

  output_dt <- merge(
    row_summary,
    row_subset,
    by = "row_id",
    all.x = TRUE,
    sort = TRUE
  )

  data.table::setorder(output_dt, row_id)

  return(output_dt)
}

#' @title Persist post-processing audit workbooks
#' @description Writes deterministic Excel outputs under
#' `audit_root_dir/audit` for clean/harmonize/standardize stage audits, and
#' writes a final-stage row subset under `audit_root_dir/diagnostics` capturing
#' all `last_rule_wins` overwrite events.
#' @param clean_audit_dt Clean-stage audit table.
#' @param harmonize_audit_dt Harmonize-stage audit table.
#' @param standardize_audit_dt Standardize-stage audit table.
#' @param standardize_rules_dt Standardize stage rule table.
#' @param standardize_matched_rule_counts_dt Standardize-stage matched-rule
#'   counts keyed by standardized rule keys.
#' @param final_stage_dt Final post-processing data.table/data.frame.
#' @param last_rule_wins_overwrites_dt Overwrite events table collected during
#'   post-processing rule execution.
#' @param config Named configuration list.
#' @return Named character vector containing clean/harmonize/standardize and
#'   `last_rule_wins_overwrites` workbook
#'   paths.
#' @importFrom checkmate assert_data_frame assert_list
#' @importFrom fs path
#' @importFrom writexl write_xlsx
persist_postpro_audit <- function(
  clean_audit_dt,
  harmonize_audit_dt,
  standardize_audit_dt,
  standardize_rules_dt,
  standardize_matched_rule_counts_dt = data.table::data.table(),
  final_stage_dt,
  last_rule_wins_overwrites_dt,
  config
) {
  checkmate::assert_data_frame(clean_audit_dt, min.rows = 0)
  checkmate::assert_data_frame(harmonize_audit_dt, min.rows = 0)
  checkmate::assert_data_frame(standardize_audit_dt, min.rows = 0)
  checkmate::assert_data_frame(standardize_rules_dt, min.rows = 0)
  checkmate::assert_data_frame(standardize_matched_rule_counts_dt, min.rows = 0)
  checkmate::assert_data_frame(final_stage_dt, min.rows = 0)
  checkmate::assert_data_frame(last_rule_wins_overwrites_dt, min.rows = 0)
  checkmate::assert_list(config, min.len = 1)

  diagnostics <- build_postpro_diagnostics(
    clean_audit_dt = clean_audit_dt,
    harmonize_audit_dt = harmonize_audit_dt,
    standardize_audit_dt = standardize_audit_dt
  )

  audit_paths <- initialize_postpro_output_root(config)
  audit_dir <- audit_paths$audit_dir
  diagnostics_dir <- audit_paths$diagnostics_dir
  ensure_directories_exist(audit_dir, recurse = TRUE)
  ensure_directories_exist(diagnostics_dir, recurse = TRUE)

  output_paths <- c(
    clean_audit = fs::path(
      audit_dir,
      get_pipeline_constants()$postpro$clean_audit_file_name
    ),
    harmonize_audit = fs::path(
      audit_dir,
      get_pipeline_constants()$postpro$harmonize_audit_file_name
    ),
    standardize_audit = fs::path(
      audit_dir,
      get_pipeline_constants()$postpro$standardize_audit_file_name
    ),
    last_rule_wins_overwrites = fs::path(
      diagnostics_dir,
      get_pipeline_constants()$postpro$last_rule_wins_overwrites_file_name
    )
  )

  last_rule_wins_subset_dt <- build_last_rule_wins_overwrite_subset(
    final_stage_dt = final_stage_dt,
    overwrite_events_dt = last_rule_wins_overwrites_dt
  )

  clean_rule_catalog_dt <- build_stage_rule_catalog_from_payloads(
    load_stage_rule_payloads(config = config, stage_name = "clean")
  )
  harmonize_rule_catalog_dt <- build_stage_rule_catalog_from_payloads(
    load_stage_rule_payloads(config = config, stage_name = "harmonize")
  )
  standardize_rule_catalog_dt <- build_standardize_rule_catalog(
    layer_rules_dt = standardize_rules_dt
  )

  clean_unmatched_summary <- build_unmatched_rule_summary(
    rule_catalog_dt = clean_rule_catalog_dt,
    matched_rule_summary_dt = diagnostics$clean_rule_summary
  )
  harmonize_unmatched_summary <- build_unmatched_rule_summary(
    rule_catalog_dt = harmonize_rule_catalog_dt,
    matched_rule_summary_dt = diagnostics$harmonize_rule_summary
  )
  standardize_unmatched_summary <- build_unmatched_standardize_rule_summary(
    rule_catalog_dt = standardize_rule_catalog_dt,
    matched_rule_summary_dt = diagnostics$standardize_rule_summary,
    matched_rule_counts_dt = standardize_matched_rule_counts_dt
  )

  writexl::write_xlsx(
    list(
      matched_rules = data.table::as.data.table(diagnostics$clean_rule_summary),
      unmatched_rules = data.table::as.data.table(clean_unmatched_summary)
    ),
    path = output_paths[["clean_audit"]]
  )

  writexl::write_xlsx(
    list(
      matched_rules = data.table::as.data.table(
        diagnostics$harmonize_rule_summary
      ),
      unmatched_rules = data.table::as.data.table(harmonize_unmatched_summary)
    ),
    path = output_paths[["harmonize_audit"]]
  )

  writexl::write_xlsx(
    list(
      matched_rules = data.table::as.data.table(
        diagnostics$standardize_rule_summary
      ),
      unmatched_rules = data.table::as.data.table(standardize_unmatched_summary)
    ),
    path = output_paths[["standardize_audit"]]
  )

  writexl::write_xlsx(
    list(
      last_rule_wins_overwrites = data.table::as.data.table(
        last_rule_wins_subset_dt
      )
    ),
    path = output_paths[["last_rule_wins_overwrites"]]
  )

  return(output_paths)
}
