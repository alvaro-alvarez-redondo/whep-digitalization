# validation helpers for import pipeline
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

detect_duplicates_dt <- function(dt) {
  dt_work <- ensure_data_table(dt)

  dup_counts <- dt_work[,
    .(duplicate_count = .N),
    by = .(commodity, variable, year, value, document)
  ]

  dup_rows <- dup_counts[duplicate_count > 1]

  errors <- if (nrow(dup_rows) > 0) {
    paste0(
      "duplicate entries detected for commodity '",
      dup_rows$commodity,
      "', variable '",
      dup_rows$variable,
      "', year '",
      dup_rows$year,
      "', value '",
      dup_rows$value,
      "', duplicate_count '",
      dup_rows$duplicate_count,
      "' in document '",
      dup_rows$document,
      "'"
    )
  } else {
    character(0)
  }

  return(list(errors = errors, data = dt_work))
}

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
