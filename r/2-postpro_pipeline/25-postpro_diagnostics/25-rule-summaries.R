#' Summarize stage audit rules into a canonical table
#' Normalizes a stage audit table into a row-level mirror of the rule
#' dictionary, ensuring all canonical columns are present and ordered.
#' @param audit_dt `data.frame`/`data.table` stage audit table.
#' @param stage_name Character scalar stage label (e.g., `"clean"` or
#'   `"harmonize"`).
#' @return `data.table` with one row per audit record.
#' @examples
#' \dontrun{
#' summarize_stage_rules(audit_dt, "clean")
#' }
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
