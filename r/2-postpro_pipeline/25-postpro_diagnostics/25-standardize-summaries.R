# script: post-processing diagnostics — standardize rule summaries
# description: standardize-layer rule catalog + matched/unmatched summaries
# (build_standardize_rule_catalog, summarize_standardize_rules,
# build_unmatched_standardize_rule_summary). Split from 25-rule-summaries.R
# (>500-line policy); pure definitions sourced with the rest of the
# 25-postpro_diagnostics stage.

#' @title Build standardize rule catalog from standardized layer rules
#' @description Converts standardization rules to standardize audit columns.
#' @param layer_rules_dt Standardize-layer rules table.
#' @return `data.table` with standardize audit rule columns.
build_standardize_rule_catalog <- function(layer_rules_dt) {
  if (!is.data.frame(layer_rules_dt) || nrow(layer_rules_dt) == 0L) {
    return(data.table::data.table(
      rule_file_identifier = character(),
      commodity_key = character(),
      unit_source = character(),
      unit_target = character(),
      unit_factor = numeric(),
      unit_offset = numeric(),
      source_unit_raw = character(),
      detected_prefix = numeric(),
      unit_factor_effective = numeric()
    ))
  }

  rules_dt <- data.table::as.data.table(data.table::copy(layer_rules_dt))

  if (!"source_rule_file" %in% names(rules_dt)) {
    rules_dt[, source_rule_file := NA_character_]
  }

  if (!"unit_source" %in% names(rules_dt)) {
    rules_dt[, unit_source := NA_character_]
  }

  if (!"unit_target" %in% names(rules_dt)) {
    rules_dt[, unit_target := NA_character_]
  }

  if (!"commodity_key" %in% names(rules_dt)) {
    rules_dt[, commodity_key := NA_character_]
  }

  if (!"unit_factor" %in% names(rules_dt)) {
    rules_dt[, unit_factor := NA_real_]
  }

  if (!"unit_offset" %in% names(rules_dt)) {
    rules_dt[, unit_offset := NA_real_]
  }

  if (!"source_unit_raw" %in% names(rules_dt)) {
    rules_dt[, source_unit_raw := NA_character_]
  }

  if (!"detected_prefix" %in% names(rules_dt)) {
    rules_dt[, detected_prefix := NA_real_]
  }

  if (!"unit_factor_effective" %in% names(rules_dt)) {
    rules_dt[, unit_factor_effective := NA_real_]
  }

  catalog_dt <- rules_dt[, .(
    rule_file_identifier = as.character(source_rule_file),
    commodity_key = as.character(commodity_key),
    unit_source = as.character(unit_source),
    unit_target = as.character(unit_target),
    unit_factor = as.numeric(unit_factor),
    unit_offset = as.numeric(unit_offset),
    source_unit_raw = as.character(source_unit_raw),
    detected_prefix = as.numeric(detected_prefix),
    unit_factor_effective = as.numeric(unit_factor_effective)
  )]

  character_columns <- c(
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target",
    "source_unit_raw"
  )
  for (column_name in character_columns) {
    catalog_dt[, (column_name) := as.character(get(column_name))]
    catalog_dt[trimws(get(column_name)) == "", (column_name) := NA_character_]
  }

  meaningful_rule_mask <-
    !is.na(catalog_dt$commodity_key) |
    !is.na(catalog_dt$unit_source) |
    !is.na(catalog_dt$unit_target)

  return(unique(catalog_dt[meaningful_rule_mask]))
}

#' @title Summarize standardize audit records
#' @description Normalizes standardize audit records into a row-level mirror of
#' the standardization rule dictionary, preserving affected-row detail.
#' @param audit_dt Standardize audit data.table from standardize stage.
#' @return `data.table` with one row per standardize audit record.
summarize_standardize_rules <- function(audit_dt) {
  stage_audit_dt <- data.table::as.data.table(audit_dt)

  required_columns <- c(
    "affected_rows",
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset",
    "source_unit_raw",
    "detected_prefix",
    "unit_factor_effective"
  )

  missing_columns <- setdiff(required_columns, names(stage_audit_dt))
  if (length(missing_columns) > 0L) {
    for (column_name in missing_columns) {
      if (column_name %in% c("affected_rows")) {
        stage_audit_dt[, (column_name) := NA_integer_]
      } else if (
        column_name %in%
          c(
            "unit_factor",
            "unit_offset",
            "detected_prefix",
            "unit_factor_effective"
          )
      ) {
        stage_audit_dt[, (column_name) := NA_real_]
      } else {
        stage_audit_dt[, (column_name) := NA_character_]
      }
    }
  }

  stage_audit_dt[,
    affected_rows := suppressWarnings(as.integer(affected_rows))
  ]
  stage_audit_dt[is.na(affected_rows), affected_rows := 0L]
  stage_audit_dt[,
    unit_factor := suppressWarnings(as.numeric(unit_factor))
  ]
  stage_audit_dt[, unit_offset := suppressWarnings(as.numeric(unit_offset))]
  stage_audit_dt[,
    detected_prefix := suppressWarnings(as.numeric(detected_prefix))
  ]
  stage_audit_dt[,
    unit_factor_effective := suppressWarnings(as.numeric(unit_factor_effective))
  ]

  for (column_name in c(
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target",
    "source_unit_raw"
  )) {
    stage_audit_dt[, (column_name) := as.character(get(column_name))]
    stage_audit_dt[
      trimws(get(column_name)) == "",
      (column_name) := NA_character_
    ]
  }

  if (nrow(stage_audit_dt) == 0L) {
    return(data.table::data.table(
      affected_rows = integer(),
      rule_file_identifier = character(),
      commodity_key = character(),
      unit_source = character(),
      unit_target = character(),
      unit_factor = numeric(),
      unit_offset = numeric(),
      source_unit_raw = character(),
      detected_prefix = numeric(),
      unit_factor_effective = numeric()
    ))
  }

  ordered_columns <- c(
    "affected_rows",
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset",
    "source_unit_raw",
    "detected_prefix",
    "unit_factor_effective"
  )

  return(stage_audit_dt[order(
    rule_file_identifier,
    commodity_key,
    unit_source,
    unit_target
  )][, ..ordered_columns])
}

#' @title Build unmatched standardize rule summary table
#' @description Computes standardization rules that never produced a successful
#' match event.
#' @param rule_catalog_dt Standardize stage rule catalog.
#' @param matched_rule_summary_dt Standardize matched-rule summary table.
#' @param matched_rule_counts_dt Optional matched-rule counts keyed by
#' `rule_commodity_match_key` and `unit_source_key`.
#' @return `data.table` in standardize audit schema with `affected_rows = 0`.
build_unmatched_standardize_rule_summary <- function(
  rule_catalog_dt,
  matched_rule_summary_dt,
  matched_rule_counts_dt = data.table::data.table()
) {
  if (!is.data.frame(rule_catalog_dt) || nrow(rule_catalog_dt) == 0L) {
    return(data.table::data.table(
      affected_rows = integer(),
      rule_file_identifier = character(),
      commodity_key = character(),
      unit_source = character(),
      unit_target = character(),
      unit_factor = numeric(),
      unit_offset = numeric(),
      source_unit_raw = character(),
      detected_prefix = numeric(),
      unit_factor_effective = numeric()
    ))
  }

  rule_catalog_dt <- data.table::as.data.table(data.table::copy(
    rule_catalog_dt
  ))
  matched_rule_summary_dt <- data.table::as.data.table(data.table::copy(
    matched_rule_summary_dt
  ))
  matched_rule_counts_dt <- data.table::as.data.table(data.table::copy(
    matched_rule_counts_dt
  ))

  key_columns <- c(
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset",
    "source_unit_raw",
    "detected_prefix",
    "unit_factor_effective"
  )

  for (column_name in c(
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target"
  )) {
    if (!column_name %in% names(rule_catalog_dt)) {
      rule_catalog_dt[, (column_name) := NA_character_]
    }

    if (!column_name %in% names(matched_rule_summary_dt)) {
      matched_rule_summary_dt[, (column_name) := NA_character_]
    }

    rule_catalog_dt[, (column_name) := as.character(get(column_name))]
    matched_rule_summary_dt[, (column_name) := as.character(get(column_name))]
  }

  for (column_name in c(
    "unit_factor",
    "unit_offset",
    "detected_prefix",
    "unit_factor_effective"
  )) {
    if (!column_name %in% names(rule_catalog_dt)) {
      rule_catalog_dt[, (column_name) := NA_real_]
    }

    if (!column_name %in% names(matched_rule_summary_dt)) {
      matched_rule_summary_dt[, (column_name) := NA_real_]
    }

    rule_catalog_dt[,
      (column_name) := suppressWarnings(as.numeric(get(column_name)))
    ]
    matched_rule_summary_dt[,
      (column_name) := suppressWarnings(as.numeric(get(column_name)))
    ]
  }

  for (column_name in c("source_unit_raw")) {
    if (!column_name %in% names(rule_catalog_dt)) {
      rule_catalog_dt[, (column_name) := NA_character_]
    }

    if (!column_name %in% names(matched_rule_summary_dt)) {
      matched_rule_summary_dt[, (column_name) := NA_character_]
    }

    rule_catalog_dt[, (column_name) := as.character(get(column_name))]
    matched_rule_summary_dt[, (column_name) := as.character(get(column_name))]
  }

  rule_catalog_dt[, rule_commodity_match_key := normalize_string(commodity_key)]
  rule_catalog_dt[, unit_source_key := normalize_string(unit_source)]

  rule_key_dt <- unique(rule_catalog_dt[, ..key_columns])

  use_rule_key_counts <-
    nrow(matched_rule_counts_dt) > 0L &&
    all(
      c("rule_commodity_match_key", "unit_source_key") %in%
        names(matched_rule_counts_dt)
    )

  matched_key_dt <- if (use_rule_key_counts) {
    matched_rule_counts_key_dt <- unique(matched_rule_counts_dt[, .(
      rule_commodity_match_key = normalize_string(rule_commodity_match_key),
      unit_source_key = normalize_string(unit_source_key)
    )])

    unique(merge(
      rule_catalog_dt,
      matched_rule_counts_key_dt,
      by = c("rule_commodity_match_key", "unit_source_key"),
      all = FALSE,
      sort = FALSE
    )[, ..key_columns])
  } else {
    unique(matched_rule_summary_dt[, ..key_columns])
  }

  matched_key_dt[, matched_flag := TRUE]

  unmatched_dt <- merge(
    rule_key_dt,
    matched_key_dt,
    by = key_columns,
    all.x = TRUE,
    sort = FALSE
  )[is.na(matched_flag)]

  if (nrow(unmatched_dt) == 0L) {
    return(data.table::data.table(
      affected_rows = integer(),
      rule_file_identifier = character(),
      commodity_key = character(),
      unit_source = character(),
      unit_target = character(),
      unit_factor = numeric(),
      unit_offset = numeric(),
      source_unit_raw = character(),
      detected_prefix = numeric(),
      unit_factor_effective = numeric()
    ))
  }

  unmatched_dt[, affected_rows := 0L]

  ordered_columns <- c(
    "affected_rows",
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset",
    "source_unit_raw",
    "detected_prefix",
    "unit_factor_effective"
  )

  return(unmatched_dt[order(
    rule_file_identifier,
    commodity_key,
    unit_source,
    unit_target
  )][, ..ordered_columns])
}
