# processing functions for transforming lists of files
transform_single_file <- function(file_row, df_wide, config) {
  assert_or_abort(checkmate::check_data_frame(
    file_row,
    min.rows = 1,
    max.rows = 1
  ))
  assert_or_abort(checkmate::check_names(
    names(file_row),
    must.include = c("file_name", "yearbook", "commodity"),
    what = "names(file_row)"
  ))
  assert_or_abort(checkmate::check_data_frame(df_wide))
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))

  if (nrow(df_wide) == 0) {
    return(NULL)
  }

  commodity_name <- resolve_commodity_name(file_row, config)

  transformed <- transform_file_dt(
    df = df_wide,
    file_name = file_row[["file_name"]],
    yearbook = file_row[["yearbook"]],
    commodity_name = commodity_name,
    config = config
  )

  return(transformed)
}

process_files <- function(
  file_list_dt,
  read_data_list,
  config,
  progressor = NULL
) {
  assert_or_abort(checkmate::check_data_frame(file_list_dt))
  assert_or_abort(checkmate::check_list(read_data_list))
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))

  if (!is.null(progressor)) {
    assert_or_abort(checkmate::check_function(progressor))
  }

  expected_items <- nrow(file_list_dt)
  provided_items <- length(read_data_list)

  if (provided_items != expected_items) {
    cli::cli_abort(c(
      "{.arg read_data_list} length must match {.arg file_list_dt} rows",
      "x" = "rows in file_list_dt: {expected_items}",
      "x" = "elements in read_data_list: {provided_items}"
    ))
  }

  invalid_read_data_index <- 0L
  for (i in seq_along(read_data_list)) {
    if (!is.data.frame(read_data_list[[i]])) {
      invalid_read_data_index <- i
      break
    }
  }

  if (invalid_read_data_index > 0) {
    cli::cli_abort(c(
      "all elements in {.arg read_data_list} must be data.frame-compatible objects",
      "x" = "invalid element index: {invalid_read_data_index}"
    ))
  }

  use_parallel <- !inherits(future::plan(), "sequential") &&
    expected_items > 1L

  indices <- seq_len(expected_items)

  file_list_dt <- ensure_data_table(file_list_dt)
  file_rows_list <- lapply(indices, function(i) file_list_dt[i])

  if (use_parallel) {
    results <- future.apply::future_lapply(
      indices,
      function(index) {
        file_row <- file_rows_list[[index]]
        df_wide <- read_data_list[[index]]

        transform_single_file(file_row, df_wide, config)
      },
      future.seed = NULL
    )
  } else {
    results <- lapply(
      indices,
      function(index) {
        file_row <- file_rows_list[[index]]
        df_wide <- read_data_list[[index]]

        if (!is.null(progressor)) {
          progressor(sprintf(
            "Import Pipeline Progress: transforming %s",
            file_row[["file_name"]]
          ))
        }

        transform_single_file(file_row, df_wide, config)
      }
    )
  }

  results <- Filter(Negate(is.null), results)

  return(results)
}

transform_files_list <- function(
  file_list_dt,
  read_data_list,
  config,
  progressor = NULL
) {
  assert_or_abort(checkmate::check_data_frame(file_list_dt))
  assert_or_abort(checkmate::check_list(read_data_list))
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))

  if (!is.null(progressor)) {
    assert_or_abort(checkmate::check_function(progressor))
  }

  if (nrow(file_list_dt) != length(read_data_list)) {
    cli::cli_abort("file list row count must match read data list length")
  }

  if (nrow(file_list_dt) == 0) {
    return(build_empty_transform_result())
  }

  results <- process_files(
    file_list_dt,
    read_data_list,
    config,
    progressor = progressor
  )

  if (length(results) == 0) {
    return(build_empty_transform_result())
  }

  n_results <- length(results)
  wide_list <- vector("list", n_results)
  long_list <- vector("list", n_results)
  for (i in seq_len(n_results)) {
    wide_list[[i]] <- results[[i]][["wide_raw"]]
    long_list[[i]] <- results[[i]][["long_raw"]]
  }

  transformed <- list(
    wide_raw = data.table::rbindlist(wide_list, use.names = TRUE, fill = TRUE),
    long_raw = data.table::rbindlist(long_list, use.names = TRUE, fill = TRUE)
  )

  assert_transform_result_contract(transformed)

  return(transformed)
}
