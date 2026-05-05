export_validation_audit_report <- function(
  audit_dt,
  config,
  findings_dt = NULL,
  output_path = config$paths$data$audit$audit_file_path
) {
  assert_or_abort(checkmate::check_data_frame(audit_dt, min.rows = 0))
  assert_or_abort(checkmate::check_list(
    config,
    min.len = 1,
    any.missing = FALSE
  ))
  assert_or_abort(checkmate::check_string(output_path, min.chars = 1))

  load_audit_config(config)

  export_dt <- data.table::as.data.table(data.table::copy(audit_dt))

  # skip workbook creation when there are no rows and no findings
  if (
    nrow(export_dt) == 0 && (is.null(findings_dt) || nrow(findings_dt) == 0)
  ) {
    return(invisible(NULL))
  }

  # create source row index
  export_dt[,
    source_row_index := if ("row_index" %in% names(export_dt)) {
      row_index
    } else {
      seq_len(.N)
    }
  ]

  # sort by document
  if ("document" %in% names(export_dt)) {
    data.table::setorderv(export_dt, cols = "document", na.last = TRUE)
  }

  technical_cols <- c(
    "source_row_index",
    "row_index",
    "audit_column",
    "audit_type",
    "audit_message"
  )
  cols_to_show <- setdiff(names(export_dt), technical_cols)
  row_lookup_dt <- export_dt[, .(excel_row = .I + 1L), by = .(source_row_index)]

  if (length(cols_to_show) == 0) {
    cols_to_show <- c("source_row_index")
  }

  workbook <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(workbook, "audit_report")

  if (nrow(export_dt) == 0) {
    openxlsx::writeData(
      workbook,
      "audit_report",
      data.table::data.table(
        note = "No audit findings detected for this dataset."
      )
    )
  } else {
    openxlsx::writeData(workbook, "audit_report", export_dt[, ..cols_to_show])
  }

  # determine effective findings
  effective_findings_dt <- findings_dt
  if (
    is.null(effective_findings_dt) &&
      all(c("row_index", "audit_column") %in% names(export_dt))
  ) {
    effective_findings_dt <- unique(export_dt[, .(row_index, audit_column)])
  }

  # highlight errors if any
  if (
    !is.null(effective_findings_dt) &&
      nrow(export_dt) > 0 &&
      nrow(effective_findings_dt) > 0
  ) {
    style_config <- config$export_config$styles$error_highlight
    highlight_style <- do.call(openxlsx::createStyle, style_config)

    findings_to_style <- data.table::as.data.table(effective_findings_dt)
    findings_to_style <- findings_to_style[
      !is.na(row_index) & nzchar(audit_column)
    ]

    if (nrow(findings_to_style) > 0) {
      findings_to_style[, source_row_index := as.integer(row_index)]
      findings_to_style <- merge(
        findings_to_style,
        row_lookup_dt,
        by = "source_row_index",
        all.x = FALSE
      )
      column_index_map <- setNames(seq_along(cols_to_show), cols_to_show)
      findings_to_style <- findings_to_style[audit_column %in% cols_to_show]

      if (nrow(findings_to_style) > 0) {
        findings_to_style[, excel_col := unname(column_index_map[audit_column])]
        style_groups <- split(
          findings_to_style$excel_row,
          findings_to_style$excel_col
        )

        purrr::walk(names(style_groups), function(col_idx_chr) {
          col_idx <- as.integer(col_idx_chr)
          rows_to_paint <- style_groups[[col_idx_chr]]
          openxlsx::addStyle(
            workbook,
            sheet = "audit_report",
            style = highlight_style,
            rows = rows_to_paint,
            cols = rep(col_idx, length(rows_to_paint)),
            gridExpand = FALSE
          )
        })
      }
    }
  }

  ensure_output_directories(output_path)

  openxlsx::saveWorkbook(workbook, output_path, overwrite = TRUE)

  return(output_path)
}

#' @title create audited data output
#' @description run audit, export excel findings, and return numeric-parsed data.
#' @param dataset_dt data frame.
#' @param config audit configuration.
#' @return data.table.
#' @examples
#' dataset_dt <- data.frame(document = "a.xlsx", value = "10", stringsAsFactors = FALSE)
#' audit_data_output(dataset_dt, config)
#' @export
