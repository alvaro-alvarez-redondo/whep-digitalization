# sheet-level reading helpers

#' Compute non-empty base rows
#' Returns a logical vector indicating which rows have at least one non-missing,
#' non-empty value across the specified base columns.
#' @param read_dt `data.table` to evaluate.
#' @param base_cols Character vector of column names to check.
#' @return Logical vector with one element per row.
#' @examples
#' compute_non_empty_base_rows(
#'   data.table::data.table(a = c("x", ""), b = c(NA, "y")),
#'   c("a", "b")
#' )
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

#' Read a single Excel sheet
#' Reads one worksheet from an Excel file as text, validates required columns,
#' filters out empty rows, and tags rows with the sheet name as `variable`.
#' @param file_path Character scalar path to the Excel file.
#' @param sheet_name Character scalar worksheet name.
#' @param config Named configuration list with `column_required`.
#' @return Named list with `data` (`data.table`) and `errors` (character).
#' @examples
#' \dontrun{
#' read_excel_sheet("data.xlsx", "Sheet1", config)
#' }
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

  read_names <- colnames(read_dt)
  normalized_names <- normalize_header_names(read_names)

  normalization_errors <- validate_header_normalization(
    header_names = read_names,
    normalized_header_names = normalized_names,
    file_path = file_path,
    sheet_name = sheet_name
  )

  if (length(normalization_errors) > 0) {
    return(create_empty_read_result(normalization_errors))
  }

  canonical_names <- config$column_required
  if (!is.null(config$column_id)) {
    canonical_names <- unique(c(canonical_names, config$column_id))
  }
  canonical_names <- canonical_names[
    !is.na(canonical_names) & nzchar(canonical_names)
  ]

  rename_pairs <- resolve_canonical_header_renames(
    header_names = read_names,
    normalized_header_names = normalized_names,
    canonical_names = canonical_names
  )

  if (length(rename_pairs$old) > 0) {
    data.table::setnames(
      read_dt,
      old = rename_pairs$old,
      new = rename_pairs$new
    )
    read_names <- colnames(read_dt)
  }

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

#' Read all sheets from an Excel file
#' Discovers worksheet names (or uses provided names), reads each sheet,
#' and row-binds the results into a single `data.table`.
#' @param file_path Character scalar path to the Excel file.
#' @param config Named configuration list with `column_required`.
#' @param sheet_names Optional character vector of sheet names to read.
#' @return Named list with `data` (`data.table`) and `errors` (character).
#' @examples
#' \dontrun{
#' read_file_sheets("data.xlsx", config)
#' }
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
