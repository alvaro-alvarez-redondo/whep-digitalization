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
#' @param current_year Optional integer scalar reference year. `NULL` (the
#'   default) resolves it from the system clock. Callers validating many
#'   tables in one run pass it once — `Sys.Date()` resolves the Windows
#'   timezone database per call, which dominates the loop otherwise.
#' @return Named list with `errors` (character vector) and `data` (original
#'   `data.table`).
#' @examples
#' \dontrun{
#' validate_year_values(long_dt)
#' }
validate_year_values <- function(dt, current_year = NULL) {
  dt_work <- ensure_data_table(dt)
  checkmate::assert_names(colnames(dt_work), must.include = "year")

  if (is.null(current_year)) {
    current_year <- as.integer(format(Sys.Date(), "%Y"))
  }
  checkmate::assert_int(current_year)
  current_year <- as.integer(current_year)
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

#' Run all long-format validations for every document in one pass
#' Vectorized equivalent of splitting a long table by `document` and running
#' `validate_long_dt()` per piece: returns the same validated data (rows
#' regrouped document-major exactly as split+rbind would) and the same error
#' vector, string for string, in the same order (per document: mandatory-field
#' errors by column then row, year errors in first-appearance order, duplicate
#' errors in group first-appearance order). Replaces a 1360-iteration loop of
#' per-document table copies and aggregations with column-level operations.
#' @param long_dt `data.frame`/`data.table` in long format with a `document`
#'   column.
#' @param config Named configuration list with `column_required`.
#' @return Named list with `data` (validated `data.table`) and `errors`.
#' @examples
#' \dontrun{
#' validate_long_dt_by_document(long_dt, config)
#' }
validate_long_dt_by_document <- function(long_dt, config) {
  checkmate::assert_data_frame(long_dt)
  checkmate::assert_list(config, any.missing = FALSE)
  checkmate::assert_character(
    config$column_required,
    any.missing = FALSE,
    min.len = 1
  )
  checkmate::assert_names(colnames(long_dt), must.include = "document")

  dt_work <- copy_as_data_table(long_dt)
  mandatory_cols <- config$column_required

  missing_mandatory_cols <- setdiff(mandatory_cols, colnames(dt_work))
  if (length(missing_mandatory_cols) > 0) {
    dt_work[, (missing_mandatory_cols) := NA_character_]
  }

  if (nrow(dt_work) == 0L) {
    # mirror the split-by-document path exactly: zero rows means zero document
    # groups, so the per-document error concatenation is NULL, not character(0)
    return(list(data = dt_work, errors = NULL))
  }

  # Document-major frame: the split() path collects each document's rows (in
  # original relative order) and concatenates the groups in first-appearance
  # order. Reproduce that permutation so downstream stable sorts see the same
  # input order; for contiguous documents it is the identity.
  document_values <- dt_work[["document"]]
  document_order <- data.table::chmatch(
    document_values,
    unique(document_values)
  )
  if (is.unsorted(document_order)) {
    dt_work <- dt_work[base::order(document_order)]
    document_values <- dt_work[["document"]]
    document_order <- data.table::chmatch(
      document_values,
      unique(document_values)
    )
  }

  row_id_in_document <- data.table::rowidv(dt_work, cols = "document")

  # error type ranks reproduce the per-document c(mandatory, year, duplicate)
  # concatenation of validate_long_dt()
  error_tables <- list()

  # --- mandatory-field errors (per document: column-major, then row) --------
  for (col_idx in seq_along(mandatory_cols)) {
    col <- mandatory_cols[[col_idx]]
    col_values <- dt_work[[col]]
    missing_mask <- is.na(col_values) | col_values == ""
    if (any(missing_mask)) {
      error_tables[[length(error_tables) + 1L]] <- data.table::data.table(
        document_rank = document_order[missing_mask],
        type_rank = 1L,
        key_a = col_idx,
        key_b = which(missing_mask),
        message = paste0(
          "missing mandatory value in document '",
          document_values[missing_mask],
          "', row_id '",
          row_id_in_document[missing_mask],
          "', column '",
          col,
          "'"
        )
      )
    }
  }

  # --- year errors (per document: first-appearance year order, range checks
  # before plain checks within one year value) -------------------------------
  checkmate::assert_names(colnames(dt_work), must.include = "year")

  current_year <- as.integer(format(Sys.Date(), "%Y"))
  min_year <- 1900L
  max_year <- current_year + 1L

  year_pairs <- unique(
    data.table::data.table(
      document_rank = document_order,
      year = dt_work[["year"]],
      appearance = seq_len(nrow(dt_work))
    ),
    by = c("document_rank", "year")
  )
  year_pairs <- year_pairs[!is.na(year) & year != ""]

  if (nrow(year_pairs) > 0L) {
    is_range <- grepl("^\\d{4}-\\d{4}$", year_pairs$year)
    is_plain <- !is_range & grepl("^\\d{4}$", year_pairs$year)

    if (any(is_range)) {
      range_pairs <- year_pairs[is_range]
      range_parts <- data.table::tstrsplit(range_pairs$year, "-", fixed = TRUE)
      range_start <- as.integer(range_parts[[1]])
      range_end <- as.integer(range_parts[[2]])

      start_after_end <- range_start > range_end
      if (any(start_after_end)) {
        error_tables[[length(error_tables) + 1L]] <- data.table::data.table(
          document_rank = range_pairs$document_rank[start_after_end],
          type_rank = 2L,
          key_a = range_pairs$appearance[start_after_end],
          key_b = 1L,
          message = paste0(
            "year range '",
            range_pairs$year[start_after_end],
            "' has start year greater than end year"
          )
        )
      }

      outside_range <- range_start < min_year | range_end > max_year
      if (any(outside_range)) {
        error_tables[[length(error_tables) + 1L]] <- data.table::data.table(
          document_rank = range_pairs$document_rank[outside_range],
          type_rank = 2L,
          key_a = range_pairs$appearance[outside_range],
          key_b = 2L,
          message = paste0(
            "year range '",
            range_pairs$year[outside_range],
            "' contains year outside plausible range [",
            min_year,
            ", ",
            max_year,
            "]"
          )
        )
      }
    }

    if (any(is_plain)) {
      plain_pairs <- year_pairs[is_plain]
      plain_years <- as.integer(plain_pairs$year)
      outside_plain <- plain_years < min_year | plain_years > max_year
      if (any(outside_plain)) {
        error_tables[[length(error_tables) + 1L]] <- data.table::data.table(
          document_rank = plain_pairs$document_rank[outside_plain],
          type_rank = 2L,
          key_a = plain_pairs$appearance[outside_plain],
          key_b = 1L,
          message = paste0(
            "year value '",
            plain_pairs$year[outside_plain],
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

  # --- duplicate errors (document is part of the identity key, so a global
  # grouping equals the per-document grouping; `by=` returns groups in
  # first-appearance order, which on the document-major frame is exactly the
  # per-document concatenation order — and .N alone keeps the grouping on the
  # GForce fast path) ---------------------------------------------------------
  identity_columns <- get_pipeline_constants()$sorting$stage_row_order
  key_columns <- intersect(identity_columns, colnames(dt_work))

  if (length(key_columns) > 0L) {
    dup_counts <- dt_work[, .(duplicate_count = .N), by = key_columns]
    dup_rows <- dup_counts[duplicate_count > 1]

    if (nrow(dup_rows) > 0L) {
      key_description_parts <- lapply(key_columns, function(column_name) {
        paste(column_name, "=", as.character(dup_rows[[column_name]]))
      })
      key_descriptions <- do.call(
        paste,
        c(key_description_parts, sep = ", ")
      )

      dup_document_rank <- if ("document" %in% key_columns) {
        data.table::chmatch(
          dup_rows[["document"]],
          unique(document_values)
        )
      } else {
        # without document in the key a global grouping cannot be attributed
        # to documents; stage_row_order always contains document, so this is
        # unreachable for pipeline data — kept as a deterministic fallback
        rep(1L, nrow(dup_rows))
      }

      error_tables[[length(error_tables) + 1L]] <- data.table::data.table(
        document_rank = dup_document_rank,
        type_rank = 3L,
        key_a = seq_len(nrow(dup_rows)),
        key_b = 1L,
        message = paste0(
          "duplicate entries detected (count ",
          dup_rows$duplicate_count,
          ") for ",
          key_descriptions
        )
      )
    }
  }

  errors <- character(0)
  if (length(error_tables) > 0L) {
    all_errors <- data.table::rbindlist(error_tables, use.names = TRUE)
    data.table::setorder(all_errors, document_rank, type_rank, key_a, key_b)
    errors <- all_errors$message
  }

  return(list(data = dt_work, errors = errors))
}

#' Run all long-format validations
#' Sequentially applies mandatory-field, year-value, and duplicate validation to
#' a long-format data table.
#' @param long_dt `data.frame`/`data.table` in long format.
#' @param config Named configuration list with `column_required`.
#' @param current_year Optional integer scalar reference year forwarded to
#'   `validate_year_values()`; `NULL` resolves it from the system clock.
#' @return Named list with `data` (validated `data.table`) and `errors`.
#' @examples
#' \dontrun{
#' validate_long_dt(long_dt, config)
#' }
validate_long_dt <- function(long_dt, config, current_year = NULL) {
  checkmate::assert_data_frame(long_dt)
  checkmate::assert_list(config, any.missing = FALSE)
  checkmate::assert_character(
    config$column_required,
    any.missing = FALSE,
    min.len = 1
  )

  mandatory_result <- validate_mandatory_fields_dt(long_dt, config)
  year_result <- validate_year_values(
    mandatory_result$data,
    current_year = current_year
  )
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
