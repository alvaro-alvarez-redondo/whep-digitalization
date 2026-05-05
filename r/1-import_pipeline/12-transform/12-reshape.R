# reshape and enrichment functions
reshape_to_long <- function(df, config) {
  data_dt <- ensure_data_table(df)
  data_dt_names <- names(data_dt)

  year_cols <- attr(data_dt, "whep_year_columns", exact = TRUE)
  if (is.null(year_cols) || !all(year_cols %in% data_dt_names)) {
    year_cols <- identify_year_columns(data_dt, config)
  }

  if (length(year_cols) == 0) {
    cli::cli_abort("no year columns were identified for reshaping")
  }

  available_id <- intersect(config$column_id, data_dt_names)

  long_dt <- data.table::melt(
    data = data_dt,
    id.vars = available_id,
    measure.vars = year_cols,
    variable.name = "year",
    value.name = "value",
    variable.factor = FALSE
  )

  return(long_dt)
}

add_metadata <- function(whep_data_long_raw, file_name, yearbook, config) {
  notes_value <- config$defaults$notes_value
  data_dt <- ensure_data_table(whep_data_long_raw)

  data.table::set(data_dt, j = "document", value = file_name)
  data.table::set(data_dt, j = "notes", value = notes_value)
  data.table::set(data_dt, j = "yearbook", value = yearbook)

  return(data_dt)
}

transform_file_dt <- function(df, file_name, yearbook, commodity_name, config) {
  assert_or_abort(checkmate::check_data_frame(df))
  assert_or_abort(checkmate::check_string(file_name, min.chars = 1))
  assert_or_abort(checkmate::check_string(yearbook, min.chars = 1))
  assert_or_abort(checkmate::check_string(commodity_name, min.chars = 1))
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))

  df_norm <- df |>
    normalize_key_fields(commodity_name, config) |>
    convert_year_columns(config)

  whep_data_long_raw <- df_norm |>
    reshape_to_long(config) |>
    add_metadata(file_name, yearbook, config) |>
    drop_na_value_rows()

  transform_result <- list(wide_raw = df_norm, long_raw = whep_data_long_raw)
  assert_transform_result_contract(transform_result)

  return(transform_result)
}

resolve_commodity_name <- function(file_row, config) {
  show_missing_commodity_metadata_warning <-
    !is.null(config$messages$show_missing_commodity_metadata_warning) &&
    isTRUE(config$messages$show_missing_commodity_metadata_warning)

  commodity_name <- as.character(file_row[["commodity"]][[1]])
  commodity_name <- trimws(commodity_name)

  if (is.na(commodity_name) || commodity_name == "") {
    if (show_missing_commodity_metadata_warning) {
      cli::cli_warn(c(
        "missing commodity metadata detected; using fallback value 'unknown'",
        "i" = "file: {file_row[['file_name']][[1]]}"
      ))
    }

    return("unknown")
  }

  return(commodity_name)
}

build_empty_transform_result <- function() {
  transform_result <- list(
    wide_raw = data.table::data.table(),
    long_raw = data.table::data.table()
  )

  assert_transform_result_contract(transform_result)

  return(transform_result)
}

assert_transform_result_contract <- function(transform_result) {
  assert_or_abort(checkmate::check_list(transform_result, any.missing = FALSE))
  assert_or_abort(checkmate::check_names(
    names(transform_result),
    must.include = c("wide_raw", "long_raw")
  ))
  assert_or_abort(checkmate::check_data_table(transform_result$wide_raw))
  assert_or_abort(checkmate::check_data_table(transform_result$long_raw))

  return(invisible(TRUE))
}
