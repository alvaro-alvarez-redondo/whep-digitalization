summarize_stage_rules <- function(audit_dt, stage_name) {
  stage_audit_dt <- data.table::as.data.table(audit_dt)

  if (
    !("value_source" %in% names(stage_audit_dt)) &&
      ("value_source_result" %in% names(stage_audit_dt))
  ) {
    stage_audit_dt[, value_source := value_source_result]
  }

  if (
    !("value_target" %in% names(stage_audit_dt)) &&
      ("value_target_result" %in% names(stage_audit_dt))
  ) {
    stage_audit_dt[, value_target := value_target_result]
  }

  required_columns <- c(
    "loop",
    "affected_rows",
    "rule_file_identifier",
    "column_source",
    "value_source_raw",
    "value_source",
    "column_target",
    "value_target_raw",
    "value_target"
  )

  missing_columns <- setdiff(required_columns, names(stage_audit_dt))
  if (length(missing_columns) > 0L) {
    for (column_name in missing_columns) {
      if (column_name %in% c("loop", "affected_rows")) {
        stage_audit_dt[, (column_name) := NA_integer_]
      } else {
        stage_audit_dt[, (column_name) := NA_character_]
      }
    }
  }

  stage_audit_dt[, loop := suppressWarnings(as.integer(loop))]
  stage_audit_dt[,
    affected_rows := suppressWarnings(as.integer(affected_rows))
  ]
  stage_audit_dt[is.na(affected_rows), affected_rows := 0L]

  if (nrow(stage_audit_dt) == 0L) {
    return(data.table::data.table(
      loop = integer(),
      affected_rows = integer(),
      rule_file_identifier = character(),
      column_source = character(),
      value_source_raw = character(),
      value_source = character(),
      column_target = character(),
      value_target_raw = character(),
      value_target = character()
    ))
  }

  ordered_columns <- c(
    "loop",
    "affected_rows",
    "rule_file_identifier",
    "column_source",
    "value_source_raw",
    "value_source",
    "column_target",
    "value_target_raw",
    "value_target"
  )

  return(stage_audit_dt[order(
    loop,
    rule_file_identifier,
    column_source,
    column_target,
    value_source_raw,
    value_target_raw
  )][, ..ordered_columns])
}

#' @title Build stage rule catalog from clean/harmonize payloads
#' @description Flattens rule payload objects into a canonical audit-ready
#' rule catalog.
#' @param rule_payloads List returned by `load_stage_rule_payloads()`.
#' @return `data.table` with canonical rule columns.
build_stage_rule_catalog_from_payloads <- function(rule_payloads) {
  if (length(rule_payloads) == 0L) {
    return(data.table::data.table(
      rule_file_identifier = character(),
      column_source = character(),
      value_source_raw = character(),
      value_source = character(),
      column_target = character(),
      value_target_raw = character(),
      value_target = character()
    ))
  }

  stage_rule_tables <- lapply(rule_payloads, function(payload) {
    raw_rules_dt <- data.table::as.data.table(payload$raw_rules)

    if (nrow(raw_rules_dt) == 0L) {
      return(raw_rules_dt[0L, ])
    }

    if (!"column_source" %in% names(raw_rules_dt)) {
      raw_rules_dt[, column_source := NA_character_]
    }

    if (!"column_target" %in% names(raw_rules_dt)) {
      raw_rules_dt[, column_target := NA_character_]
    }

    if (!"value_source_raw" %in% names(raw_rules_dt)) {
      if ("value_source" %in% names(raw_rules_dt)) {
        raw_rules_dt[, value_source_raw := as.character(value_source)]
      } else {
        raw_rules_dt[, value_source_raw := NA_character_]
      }
    }

    if (!"value_target_raw" %in% names(raw_rules_dt)) {
      if ("value_target" %in% names(raw_rules_dt)) {
        raw_rules_dt[, value_target_raw := as.character(value_target)]
      } else {
        raw_rules_dt[, value_target_raw := NA_character_]
      }
    }

    if (!"value_source" %in% names(raw_rules_dt)) {
      raw_rules_dt[, value_source := as.character(value_source_raw)]
    }

    if (!"value_target" %in% names(raw_rules_dt)) {
      raw_rules_dt[, value_target := as.character(value_target_raw)]
    }

    raw_rules_dt[, rule_file_identifier := as.character(payload$rule_file_id)]

    rule_columns <- c(
      "rule_file_identifier",
      "column_source",
      "value_source_raw",
      "value_source",
      "column_target",
      "value_target_raw",
      "value_target"
    )

    rule_dt <- raw_rules_dt[, ..rule_columns]

    for (column_name in names(rule_dt)) {
      rule_dt[, (column_name) := as.character(get(column_name))]
      rule_dt[trimws(get(column_name)) == "", (column_name) := NA_character_]
    }

    meaningful_rule_mask <-
      !is.na(rule_dt$column_source) |
      !is.na(rule_dt$value_source_raw) |
      !is.na(rule_dt$column_target) |
      !is.na(rule_dt$value_target_raw)

    rule_dt <- rule_dt[meaningful_rule_mask]

    return(rule_dt)
  })

  combined_rule_dt <- data.table::rbindlist(stage_rule_tables, fill = TRUE)

  if (nrow(combined_rule_dt) == 0L) {
    return(data.table::data.table(
      rule_file_identifier = character(),
      column_source = character(),
      value_source_raw = character(),
      value_source = character(),
      column_target = character(),
      value_target_raw = character(),
      value_target = character()
    ))
  }

  return(unique(combined_rule_dt))
}

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
      unit_offset = numeric()
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

  catalog_dt <- rules_dt[, .(
    rule_file_identifier = as.character(source_rule_file),
    commodity_key = as.character(commodity_key),
    unit_source = as.character(unit_source),
    unit_target = as.character(unit_target),
    unit_factor = as.numeric(unit_factor),
    unit_offset = as.numeric(unit_offset)
  )]

  character_columns <- c(
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target"
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
    "unit_offset"
  )

  missing_columns <- setdiff(required_columns, names(stage_audit_dt))
  if (length(missing_columns) > 0L) {
    for (column_name in missing_columns) {
      if (column_name %in% c("affected_rows")) {
        stage_audit_dt[, (column_name) := NA_integer_]
      } else if (column_name %in% c("unit_factor", "unit_offset")) {
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

  for (column_name in c(
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target"
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
      unit_offset = numeric()
    ))
  }

  ordered_columns <- c(
    "affected_rows",
    "rule_file_identifier",
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset"
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
      unit_offset = numeric()
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
    "unit_offset"
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

  for (column_name in c("unit_factor", "unit_offset")) {
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
      unit_offset = numeric()
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
    "unit_offset"
  )

  return(unmatched_dt[order(
    rule_file_identifier,
    commodity_key,
    unit_source,
    unit_target
  )][, ..ordered_columns])
}

#' @title Build unmatched rule summary table
#' @description Computes rules that never produced a successful match event.
#' @param rule_catalog_dt Canonical stage rule catalog.
#' @param matched_rule_summary_dt Canonical matched-rule summary table.
#' @return `data.table` in audit summary schema with `affected_rows = 0`.
build_unmatched_rule_summary <- function(
  rule_catalog_dt,
  matched_rule_summary_dt
) {
  if (!is.data.frame(rule_catalog_dt) || nrow(rule_catalog_dt) == 0L) {
    return(data.table::data.table(
      loop = integer(),
      affected_rows = integer(),
      rule_file_identifier = character(),
      column_source = character(),
      value_source_raw = character(),
      value_source = character(),
      column_target = character(),
      value_target_raw = character(),
      value_target = character()
    ))
  }

  rule_catalog_dt <- data.table::as.data.table(data.table::copy(
    rule_catalog_dt
  ))
  matched_rule_summary_dt <- data.table::as.data.table(data.table::copy(
    matched_rule_summary_dt
  ))

  key_columns <- c(
    "rule_file_identifier",
    "column_source",
    "value_source_raw",
    "column_target",
    "value_target_raw"
  )

  for (column_name in key_columns) {
    if (!column_name %in% names(rule_catalog_dt)) {
      rule_catalog_dt[, (column_name) := NA_character_]
    }

    if (!column_name %in% names(matched_rule_summary_dt)) {
      matched_rule_summary_dt[, (column_name) := NA_character_]
    }

    rule_catalog_dt[, (column_name) := as.character(get(column_name))]
    matched_rule_summary_dt[, (column_name) := as.character(get(column_name))]
  }

  rule_key_dt <- unique(rule_catalog_dt[, .(
    rule_file_identifier,
    column_source,
    value_source_raw,
    value_source,
    column_target,
    value_target_raw,
    value_target
  )])

  matched_key_dt <- unique(matched_rule_summary_dt[, ..key_columns])
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
      loop = integer(),
      affected_rows = integer(),
      rule_file_identifier = character(),
      column_source = character(),
      value_source_raw = character(),
      value_source = character(),
      column_target = character(),
      value_target_raw = character(),
      value_target = character()
    ))
  }

  unmatched_dt[, `:=`(
    loop = as.integer(NA),
    affected_rows = 0L
  )]

  ordered_columns <- c(
    "loop",
    "affected_rows",
    "rule_file_identifier",
    "column_source",
    "value_source_raw",
    "value_source",
    "column_target",
    "value_target_raw",
    "value_target"
  )

  return(unmatched_dt[order(
    rule_file_identifier,
    column_source,
    column_target,
    value_source_raw,
    value_target_raw
  )][, ..ordered_columns])
}

#' @title Build post-processing rule summaries
#' @description Creates stage-specific rule summaries for clean, harmonize,
#' and standardize audit tables.
#' @param clean_audit_dt Clean-stage audit table.
#' @param harmonize_audit_dt Harmonize-stage audit table.
#' @param standardize_audit_dt Standardize-stage audit table.
#' @return Named list with `clean_rule_summary`, `harmonize_rule_summary`, and
#' `standardize_rule_summary`
#' data.tables.
#' @importFrom checkmate assert_data_frame
