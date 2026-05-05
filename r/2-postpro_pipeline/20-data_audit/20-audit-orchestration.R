audit_data_output <- function(dataset_dt, config) {
  assert_or_abort(checkmate::check_data_frame(dataset_dt, min.rows = 0))
  assert_or_abort(checkmate::check_list(config, min.len = 1))

  load_audit_config(config)

  audit_output_dir <- config$paths$data$audit$audit_dir

  assert_or_abort(checkmate::check_string(audit_output_dir, min.chars = 1))

  prepare_audit_root(audit_output_dir)

  audit_result <- run_master_validation(
    dataset_dt,
    resolve_audit_columns_by_type(config)
  )

  invalid_index <- audit_result$invalid_row_index

  prepared_paths <- resolve_audit_output_paths(
    audit_root_dir = audit_output_dir,
    audit_file_name = fs::path_file(config$paths$data$audit$audit_file_path)
  )

  # subset invalid rows (may be zero rows)
  audit_dt <- dataset_dt[invalid_index, , drop = FALSE]

  # remap findings row_index to local subset positions
  findings_dt <- data.table::as.data.table(audit_result$findings)

  if (nrow(findings_dt) > 0) {
    findings_dt[, row_index := match(row_index, invalid_index)]
  }

  has_findings <- nrow(findings_dt) > 0

  if (has_findings) {
    export_validation_audit_report(
      audit_dt = audit_dt,
      config = config,
      findings_dt = findings_dt,
      output_path = prepared_paths$audit_file_path
    )
  }

  audited_dt <- data.table::as.data.table(dataset_dt)

  if ("value" %in% names(audited_dt)) {
    audited_dt[,
      value := suppressWarnings(readr::parse_double(as.character(value)))
    ]
  }

  return(audited_dt)
}
