build_standardize_layer_audit <- function(
  layer_rules_dt,
  matched_rule_counts_dt,
  source_paths
) {
  checkmate::assert_data_frame(layer_rules_dt, min.rows = 0)
  checkmate::assert_data_frame(matched_rule_counts_dt, min.rows = 0)
  checkmate::assert_character(source_paths, any.missing = FALSE)

  audit_columns <- c(
    "affected_rows",
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset"
  )

  if (nrow(layer_rules_dt) == 0L) {
    empty_audit_dt <- data.table::data.table(
      affected_rows = integer(),
      rule_file_identifier = character(),
      commodity_key = character(),
      unit_source = character(),
      unit_target = character(),
      unit_factor = numeric(),
      unit_offset = numeric()
    )

    return(empty_audit_dt[, ..audit_columns])
  }

  rules_dt <- data.table::as.data.table(data.table::copy(layer_rules_dt))
  matched_counts_dt <- data.table::as.data.table(data.table::copy(
    matched_rule_counts_dt
  ))

  if (!"source_rule_file" %in% names(rules_dt)) {
    if (length(source_paths) > 0L) {
      rules_dt[, source_rule_file := fs::path_file(source_paths[[1]])]
    } else {
      rules_dt[, source_rule_file := NA_character_]
    }
  }

  if (!"source_rule_sheet" %in% names(rules_dt)) {
    rules_dt[, source_rule_sheet := NA_character_]
  }

  if (!"commodity_match_key" %in% names(rules_dt)) {
    rules_dt[, commodity_match_key := normalize_string(commodity_key)]
  }

  if (!"unit_source_key" %in% names(rules_dt)) {
    rules_dt[, unit_source_key := normalize_string(unit_source)]
  }

  if (
    !all(
      c(
        "rule_commodity_match_key",
        "applied_commodity_match_key",
        "unit_source_key"
      ) %in%
        names(matched_counts_dt)
    )
  ) {
    matched_counts_dt <- data.table::data.table(
      rule_commodity_match_key = character(),
      applied_commodity_match_key = character(),
      unit_source_key = character(),
      affected_rows = integer()
    )
  }

  if (!"affected_rows" %in% names(matched_counts_dt)) {
    matched_counts_dt[, affected_rows := integer(.N)]
  }

  audit_matched_dt <- merge(
    rules_dt,
    matched_counts_dt,
    by.x = c("commodity_match_key", "unit_source_key"),
    by.y = c("rule_commodity_match_key", "unit_source_key"),
    all.x = FALSE,
    all.y = FALSE
  )

  if (nrow(audit_matched_dt) == 0L) {
    empty_audit_dt <- data.table::data.table(
      affected_rows = integer(),
      rule_file_identifier = character(),
      commodity_key = character(),
      unit_source = character(),
      unit_target = character(),
      unit_factor = numeric(),
      unit_offset = numeric()
    )

    return(empty_audit_dt[, ..audit_columns])
  }

  audit_dt <- audit_matched_dt[, .(
    affected_rows = as.integer(affected_rows),
    rule_file_identifier = as.character(source_rule_file),
    commodity_key = as.character(applied_commodity_match_key),
    unit_source = as.character(unit_source),
    unit_target = as.character(unit_target),
    unit_factor = as.numeric(unit_factor),
    unit_offset = as.numeric(unit_offset)
  )]

  return(audit_dt[, ..audit_columns])
}

#' @title load units standardization rules
#' @description Ensures template availability and loads prepared conversion rules
#' from standardization import files.
#' @param config named configuration list.
#' @return named list with `layer_rules`, `source_path`, and `template_path`.
#' @importFrom checkmate assert_list assert_string
#' @examples
#' \dontrun{load_units_standardization_rules(config)}
load_units_standardization_rules <- function(config) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(
    config$paths$data$import$standardization,
    min.chars = 1
  )

  template_path <- ensure_standardize_template_exists(config)
  raw_rules_payload <- read_all_standardize_rule_files(config)
  prepared_rules <- prepare_standardize_rules(raw_rules_payload$rules)

  source_paths <- if (length(raw_rules_payload$source_paths) > 0L) {
    raw_rules_payload$source_paths
  } else {
    template_path
  }

  return(list(
    layer_rules = prepared_rules,
    source_path = source_paths,
    template_path = template_path
  ))
}

#' @title run units standardization layer batch
#' @description Orchestrates standardization rule loading, conversion execution,
#' optional post-standardization row aggregation, and diagnostics attachment.
#' @param clean_dt clean data.table/data.frame.
#' @param config named configuration list.
#' @param unit_column character scalar unit column name.
#' @param value_column character scalar numeric value column name.
#' @param commodity_column character scalar commodity column name.
#' @param aggregate_after_standardize Logical scalar toggle for post-
#' standardization row aggregation. When `TRUE` (default), rows that are
#' identical on every column except `value_column` are collapsed by summing
#' the numeric measure.
#' @return standardized data.table with diagnostics attached.
#' @importFrom checkmate assert_data_frame assert_list assert_string
#'  assert_flag
#' @examples
#' \dontrun{run_units_standardization_layer_batch(clean_dt, config)}
run_standardize_units_layer_batch <- function(
  clean_dt,
  config,
  unit_column = "unit",
  value_column = "value",
  commodity_column = "commodity",
  aggregate_after_standardize = TRUE
) {
  checkmate::assert_data_frame(clean_dt, min.rows = 0)
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(unit_column, min.chars = 1)
  checkmate::assert_string(value_column, min.chars = 1)
  checkmate::assert_string(commodity_column, min.chars = 1)
  checkmate::assert_flag(aggregate_after_standardize)

  layer_payload <- load_units_standardization_rules(config)

  apply_result <- apply_standardize_rules(
    mapped_dt = clean_dt,
    prepared_rules_dt = layer_payload$layer_rules,
    unit_column = unit_column,
    value_column = value_column,
    commodity_column = commodity_column
  )

  rows_before_aggregation <- nrow(apply_result$data)
  aggregated_source_rows_dt <- data.table::as.data.table(apply_result$data)[
    0L,
  ]
  if (aggregate_after_standardize && rows_before_aggregation > 0L) {
    pre_agg_dt <- data.table::as.data.table(apply_result$data)
    aggregated_source_rows_dt <- extract_aggregated_rows(
      pre_agg_dt,
      value_column = value_column
    )
    apply_result$data <- aggregate_standardized_rows(
      pre_agg_dt,
      value_column = value_column
    )
  }
  rows_after_aggregation <- nrow(apply_result$data)

  normalize_dt <- attach_standardize_diagnostics(
    standardized_dt = apply_result$data,
    clean_rows_count = nrow(clean_dt),
    matched_count = as.integer(apply_result$matched_count),
    unmatched_count = as.integer(apply_result$unmatched_count),
    rules_count = as.integer(nrow(layer_payload$layer_rules)),
    rule_sources = as.character(layer_payload$source_path),
    aggregation_enabled = aggregate_after_standardize,
    rows_before_aggregation = as.integer(rows_before_aggregation),
    rows_after_aggregation = as.integer(rows_after_aggregation)
  )

  attr(normalize_dt, "layer_audit") <- build_standardize_layer_audit(
    layer_rules_dt = layer_payload$layer_rules,
    matched_rule_counts_dt = apply_result$matched_rule_counts,
    source_paths = as.character(layer_payload$source_path)
  )

  attr(normalize_dt, "layer_rules") <- layer_payload$layer_rules
  attr(normalize_dt, "layer_matched_rule_counts") <-
    apply_result$matched_rule_counts

  attr(normalize_dt, "aggregated_source_rows") <- aggregated_source_rows_dt

  return(normalize_dt)
}
