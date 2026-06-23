# validation helpers for import pipeline

#' Validate mandatory fields in a data table
#' Checks that all `config$column_required` columns are present and non-empty,
#' filling missing columns with `NA_character_` and reporting errors per row.
#' @param dt `data.frame`/`data.table` to validate.
#' @param config Named configuration list with `column_required`.
#' @return Named list with `errors` (character vector) and `data` (modified
#'   `data.table`).
#' @examples
#' \dontrun{
#' validate_mandatory_fields_dt(long_dt, config)
#' }
validate_mandatory_fields_dt <- function(dt, config) {
  dt_work <- copy_as_data_table(dt)
  mandatory_cols <- config$column_required
  constants <- get_pipeline_constants()

  missing_mandatory_cols <- setdiff(mandatory_cols, colnames(dt_work))

  if (length(missing_mandatory_cols) > 0) {
    dt_work[, (missing_mandatory_cols) := NA_character_]
  }

  if (!"document" %in% colnames(dt_work)) {
    dt_work[, document := constants$defaults$unknown_document]
  }

  document_values <- dt_work[["document"]]
  row_ids <- seq_len(nrow(dt_work))

  error_parts <- vector("list", length(mandatory_cols))
  for (col_idx in seq_along(mandatory_cols)) {
    col <- mandatory_cols[[col_idx]]
    col_values <- dt_work[[col]]
    missing_mask <- is.na(col_values) | col_values == ""
    if (any(missing_mask)) {
      error_parts[[col_idx]] <- paste0(
        "missing mandatory value in document '",
        document_values[missing_mask],
        "', row_id '",
        row_ids[missing_mask],
        "', column '",
        col,
        "'"
      )
    }
  }

  errors <- unique(unlist(error_parts, use.names = FALSE))
  if (is.null(errors)) {
    errors <- character(0)
  }

  return(list(errors = errors, data = dt_work))
}

#' Detect duplicate rows in a data table
#' Identifies rows that are duplicated across `commodity`, `variable`, `year`,
#' `value`, and `document`.
#' @param dt `data.frame`/`data.table` to inspect.
#' @return Named list with `errors` (character vector) and `data` (original
#'   `data.table`).
#' @examples
#' \dontrun{
#' detect_duplicates_dt(long_dt)
#' }
detect_duplicates_dt <- function(dt) {
  dt_work <- ensure_data_table(dt)

  # A genuine duplicate is a row that repeats the full observation identity, not
  # just a subset of it. Keying on only commodity/variable/year/value/document
  # (omitting hemisphere/continent/polity/unit) flags legitimately distinct rows
  # — e.g. the same commodity/year reported by two polities, or in two units —
  # as duplicates. Key on every identity column present, in canonical order.
  identity_columns <- get_pipeline_constants()$sorting$stage_row_order
  key_columns <- intersect(identity_columns, colnames(dt_work))

  if (length(key_columns) == 0L) {
    return(list(errors = character(0), data = dt_work))
  }

  dup_counts <- dt_work[,
    .(duplicate_count = .N),
    by = key_columns
  ]

  dup_rows <- dup_counts[duplicate_count > 1]

  errors <- if (nrow(dup_rows) > 0) {
    key_descriptions <- vapply(
      seq_len(nrow(dup_rows)),
      function(row_index) {
        paste(
          key_columns,
          "=",
          vapply(
            key_columns,
            function(column_name) {
              as.character(dup_rows[[column_name]][[row_index]])
            },
            character(1)
          ),
          collapse = ", "
        )
      },
      character(1)
    )

    paste0(
      "duplicate entries detected (count ",
      dup_rows$duplicate_count,
      ") for ",
      key_descriptions
    )
  } else {
    character(0)
  }

  return(list(errors = errors, data = dt_work))
}

#' Validate year values in a data table
#' Checks that year values are within the plausible range `[1900, current_year + 1]`
#' and that year ranges have a start year less than or equal to the end year.
#' @param dt `data.frame`/`data.table` with a `year` column.
#' @return Named list with `errors` (character vector) and `data` (original
#'   `data.table`).
#' @examples
#' \dontrun{
#' validate_year_values(long_dt)
#' }
validate_year_values <- function(dt) {
  dt_work <- ensure_data_table(dt)
  checkmate::assert_names(colnames(dt_work), must.include = "year")

  current_year <- as.integer(format(Sys.Date(), "%Y"))
  min_year <- 1900L
  max_year <- current_year + 1L

  year_values <- unique(dt_work[["year"]])
  year_values <- year_values[!is.na(year_values) & year_values != ""]

  errors <- character(0)

  for (yr in year_values) {
    if (grepl("^\\d{4}-\\d{4}$", yr)) {
      parts <- strsplit(yr, "-", fixed = TRUE)[[1]]
      start_yr <- as.integer(parts[1])
      end_yr <- as.integer(parts[2])

      if (start_yr > end_yr) {
        errors <- c(
          errors,
          paste0(
            "year range '",
            yr,
            "' has start year greater than end year"
          )
        )
      }

      if (start_yr < min_year || end_yr > max_year) {
        errors <- c(
          errors,
          paste0(
            "year range '",
            yr,
            "' contains year outside plausible range [",
            min_year,
            ", ",
            max_year,
            "]"
          )
        )
      }
    } else if (grepl("^\\d{4}$", yr)) {
      yr_int <- as.integer(yr)
      if (yr_int < min_year || yr_int > max_year) {
        errors <- c(
          errors,
          paste0(
            "year value '",
            yr,
            "' is outside plausible range [",
            min_year,
            ", ",
            max_year,
            "]"
          )
        )
      }
    }
  }

  return(list(errors = errors, data = dt_work))
}

#' Run all long-format validations
#' Sequentially applies mandatory-field, year-value, and duplicate validation to
#' a long-format data table.
#' @param long_dt `data.frame`/`data.table` in long format.
#' @param config Named configuration list with `column_required`.
#' @return Named list with `data` (validated `data.table`) and `errors`.
#' @examples
#' \dontrun{
#' validate_long_dt(long_dt, config)
#' }
validate_long_dt <- function(long_dt, config) {
  checkmate::assert_data_frame(long_dt)
  checkmate::assert_list(config, any.missing = FALSE)
  checkmate::assert_character(
    config$column_required,
    any.missing = FALSE,
    min.len = 1
  )

  mandatory_result <- validate_mandatory_fields_dt(long_dt, config)
  year_result <- validate_year_values(mandatory_result$data)
  duplicate_result <- detect_duplicates_dt(year_result$data)

  return(list(
    data = mandatory_result$data,
    errors = c(
      mandatory_result$errors,
      year_result$errors,
      duplicate_result$errors
    )
  ))
}
