# transform utility functions

#' Identify year columns in a data table
#' Detects columns whose names match the year-column regex pattern, excluding
#' known non-year columns from the pipeline column order.
#' @param df `data.frame`/`data.table` to inspect.
#' @param config Named configuration list with `column_order`.
#' @return Character vector of year column names.
#' @examples
#' identify_year_columns(
#'   data.table::data.table(`2020` = 1, continent = "EU"),
#'   list(column_order = c("continent", "year", "value"))
#' )
identify_year_columns <- function(df, config) {
  all_cols <- names(df)
  if (length(all_cols) == 0L) {
    return(character(0))
  }

  non_year_cols <- setdiff(config$column_order, c("year", "value"))
  candidate_cols <- all_cols[!all_cols %in% non_year_cols]
  year_pattern <- get_pipeline_constants()$patterns$year_column

  year_columns <- candidate_cols[grepl(
    year_pattern,
    candidate_cols,
    perl = TRUE
  )]

  return(year_columns)
}

#' Normalize key identifier fields
#' Ensures required base columns exist, normalizes commodity and textual
#' identifiers, and cleans footnotes.
#' @param df `data.frame`/`data.table` to normalize.
#' @param commodity_name Character scalar commodity name.
#' @param config Named configuration list with `column_required`.
#' @return Modified `data.table` with normalized key fields.
#' @examples
#' \dontrun{
#' normalize_key_fields(wide_dt, "wheat", config)
#' }
normalize_key_fields <- function(df, commodity_name, config) {
  data_dt <- ensure_data_table(df)
  data_dt_names <- names(data_dt)
  base_cols <- config$column_required
  missing_cols <- setdiff(base_cols, data_dt_names)

  if (length(missing_cols) > 0) {
    data_dt[, (missing_cols) := NA_character_]
    data_dt_names <- names(data_dt)
  }

  data.table::set(
    data_dt,
    j = "commodity",
    value = normalize_string_impl(commodity_name)
  )

  norm_cols <- intersect(
    c("variable", "hemisphere", "continent", "polity"),
    data_dt_names
  )
  if (length(norm_cols) > 0L) {
    data_dt[,
      (norm_cols) := lapply(.SD, normalize_string_impl),
      .SDcols = norm_cols
    ]
  }

  if ("footnotes" %in% data_dt_names) {
    data.table::set(
      data_dt,
      j = "footnotes",
      value = clean_footnote_impl(data_dt[["footnotes"]])
    )
  }

  return(data_dt)
}

#' Convert and clean year column names
#' Removes Excel numeric suffixes from year headers, normalizes year-range
#' formats, and coerces year column values to character.
#' @param df `data.frame`/`data.table` with year columns.
#' @param config Named configuration list.
#' @return Modified `data.table` with cleaned year column names and types.
#' @examples
#' \dontrun{
#' convert_year_columns(wide_dt, config)
#' }
convert_year_columns <- function(df, config) {
  clean_names <- gsub("\\.0$", "", colnames(df))
  clean_names <- sub("^(\\d{4})-\\d{2}$", "\\1", clean_names)
  clean_names <- sub(
    "^(\\d{4})-\\d{2}/(\\d{4})-\\d{2}$",
    "\\1-\\2",
    clean_names
  )

  # Year-header normalization can map two distinct source headers onto the same
  # name (e.g. a calendar "2020" column and a crop-year "2020-21" column both
  # become "2020"). `setnames` would silently create duplicate columns, and the
  # downstream `melt` would then read only the first of them, dropping the
  # other column's observations without warning. Surface the collision instead
  # of corrupting the data, mirroring `validate_header_normalization`.
  if (anyDuplicated(clean_names) > 0L) {
    colliding_names <- unique(clean_names[duplicated(clean_names)])
    cli::cli_abort(c(
      "year-column normalization produced duplicate column names.",
      "x" = "colliding normalized name{?s}: {.val {colliding_names}}",
      "i" = "original columns: {.val {colnames(df)}}"
    ))
  }

  if (!identical(clean_names, colnames(df))) {
    data.table::setnames(df, old = colnames(df), new = clean_names)
  }

  year_cols <- identify_year_columns(df, config)
  attr(df, "whep_year_columns") <- year_cols

  if (length(year_cols) > 0) {
    non_char_cols <- year_cols[
      !vapply(year_cols, function(col) is.character(df[[col]]), logical(1))
    ]
    if (length(non_char_cols) > 0) {
      for (col in non_char_cols) {
        data.table::set(df, j = col, value = as.character(df[[col]]))
      }
    }
  }

  return(df)
}
