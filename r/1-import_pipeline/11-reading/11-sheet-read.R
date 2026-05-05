# sheet-level reading helpers
compute_non_empty_base_rows <- function(read_dt, base_cols) {
  ensure_data_table(read_dt)

  if (length(base_cols) == 0) {
    return(logical(nrow(read_dt)))
  }

  keep_row <- Reduce(
    `|`,
    lapply(base_cols, function(col) {
      v <- read_dt[[col]]
      !is.na(v) & trimws(v) != ""
    })
  )

  return(keep_row)
}

read_excel_sheet <- function(file_path, sheet_name, config) {
  assert_or_abort(checkmate::check_string(file_path, min.chars = 1))
  assert_or_abort(checkmate::check_string(sheet_name, min.chars = 1))
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))

  base_cols <- config$column_required
  assert_or_abort(checkmate::check_character(
    base_cols,
    any.missing = FALSE,
    min.len = 1
  ))

  safe_read_result <- safe_execute_read(
    operation = \() {
      readxl::read_excel(
        path = file_path,
        sheet = sheet_name,
        col_names = TRUE,
        col_types = "text",
        .name_repair = "unique_quiet"
      )
    },
    context_message = paste0(
      "failed to read sheet {.val ",
      sheet_name,
      "} in file"
    ),
    file_path = file_path
  )

  if (has_read_errors(safe_read_result)) {
    return(create_empty_read_result(safe_read_result$errors))
  }

  read_dt <- data.table::setDT(safe_read_result$result)

  missing_base <- setdiff(base_cols, colnames(read_dt))

  missing_base_errors <- if (length(missing_base) > 0) {
    cli::format_warning(c(
      "sheet {.val {sheet_name}} is missing required base columns in file {.file {fs::path_file(file_path)}}.",
      "!" = paste(missing_base, collapse = ", ")
    ))
  } else {
    character(0)
  }

  if (length(missing_base) > 0) {
    read_dt[, (missing_base) := NA_character_]
  }

  keep_row <- compute_non_empty_base_rows(
    read_dt = read_dt,
    base_cols = base_cols
  )

  filtered_dt <- read_dt[keep_row]
  filtered_dt[, variable := sheet_name]

  return(list(data = filtered_dt, errors = missing_base_errors))
}

read_file_sheets <- function(file_path, config, sheet_names = NULL) {
  assert_or_abort(checkmate::check_string(file_path, min.chars = 1))
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))

  assert_or_abort(checkmate::check_character(
    config$column_required,
    any.missing = FALSE,
    min.len = 1
  ))

  sheets <- sheet_names
  sheet_discovery_errors <- character(0)

  if (is.null(sheet_names)) {
    safe_sheet_result <- safe_execute_read(
      operation = \() readxl::excel_sheets(file_path),
      context_message = "failed to list sheets in file",
      file_path = file_path
    )

    if (has_read_errors(safe_sheet_result)) {
      return(create_empty_read_result(safe_sheet_result$errors))
    }

    sheets <- safe_sheet_result$result
  } else {
    assert_or_abort(checkmate::check_character(
      sheet_names,
      any.missing = FALSE
    ))
  }

  if (length(sheets) == 0) {
    return(create_empty_read_result())
  }

  non_ascii <- sheets[!stringi::stri_enc_isascii(sheets)]

  errors <- if (length(non_ascii) > 0) {
    cli::format_warning(c(
      "found non-ascii sheet names in file {.file {fs::path_file(file_path)}}.",
      "!" = paste(non_ascii, collapse = ", ")
    ))
  } else {
    character(0)
  }

  sheets_list <- lapply(sheets, function(sheet_name) {
    read_excel_sheet(file_path, sheet_name, config)
  })

  combined_data <- data.table::rbindlist(
    lapply(sheets_list, `[[`, "data"),
    use.names = TRUE,
    fill = TRUE
  )

  combined_errors <- c(
    sheet_discovery_errors,
    errors,
    unlist(lapply(sheets_list, `[[`, "errors"), use.names = FALSE)
  )

  return(list(data = combined_data, errors = combined_errors))
}
