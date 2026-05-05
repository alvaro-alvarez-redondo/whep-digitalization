# transform utility functions
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
    c("variable", "hemisphere", "continent", "country"),
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

convert_year_columns <- function(df, config) {
  clean_names <- gsub("\\.0$", "", colnames(df))
  clean_names <- sub("^(\\d{4})-\\d{2}$", "\\1", clean_names)
  clean_names <- sub(
    "^(\\d{4})-\\d{2}/(\\d{4})-\\d{2}$",
    "\\1-\\2",
    clean_names
  )

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
