# processing functions for transforming lists of files

#' Transform a single imported file
#' Applies normalization, reshaping, and metadata enrichment to one file's
#' wide-format data using its associated metadata row.
#' @param file_row One-row `data.frame` with `file_name`, `yearbook`, and
#'   `commodity` columns.
#' @param df_wide `data.frame` containing the raw wide-format sheet data.
#' @param config Named configuration list.
#' @return Named list with `wide_raw` and `long_raw` elements, or `NULL` if
#'   `df_wide` has zero rows.
#' @examples
#' \dontrun{
#' transform_single_file(file_list_dt[1], read_data_list[[1]], config)
#' }
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

#' Process a list of imported files
#' Iterates over paired file metadata and read data, transforming each file
#' individually. Supports parallel execution via `future.apply`.
#' @param file_list_dt `data.frame`/`data.table` of file metadata.
#' @param read_data_list List of `data.frame`s matching `file_list_dt` rows.
#' @param config Named configuration list.
#' @param progressor Optional progress-reporting function.
#' @return List of transformation results (one per file), with `NULL` results
#'   removed.
#' @examples
#' \dontrun{
#' process_files(file_list_dt, read_data_list, config)
#' }
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

  # One progress tick per file, used by BOTH branches so the import transform
  # budget closes identically in sequential and parallel mode. The tick is
  # NULL-guarded, so the perf-sensitive (progressor = NULL) paths are unchanged.
  #
  # Keep the future_lapply-over-indices structure: future.apply exports the
  # `read_data_list` global to each worker once per session, which is cheap.
  # Do NOT apply future.scheduling here (unlike the read stage) and do NOT
  # switch to future_mapply over the data: both measured ~5-6x slower on the
  # real dataset because they re-serialize the large read data per chunk. The
  # transform stage is short (~10-15s) relative to the read, so default
  # chunking's coarser relay is an acceptable trade for keeping it fast.
  transform_message_template <- get_pipeline_constants()$progress$messages$import$transform_file
  transform_one <- function(index) {
    file_row <- file_rows_list[[index]]
    df_wide <- read_data_list[[index]]

    if (!is.null(progressor)) {
      progressor(sprintf(transform_message_template, file_row[["file_name"]]))
    }

    transform_single_file(file_row, df_wide, config)
  }

  if (use_parallel) {
    results <- future.apply::future_lapply(
      indices,
      transform_one,
      future.seed = NULL
    )
  } else {
    results <- lapply(indices, transform_one)
  }

  results <- Filter(Negate(is.null), results)

  return(results)
}

#' Read and transform all pipeline files in fused batches
#' Executes read and transform as one unit of work per workbook batch: each
#' batch (worker, when a non-sequential `future` plan is active) reads its
#' workbooks via `read_workbook_batch()` and immediately transforms each file
#' via `transform_single_file()`, returning only the per-file transform
#' results and read errors. Output is identical to running
#' `read_pipeline_files()` followed by `transform_files_list()`; what changes
#' is the execution shape — the bulky intermediate read data never crosses
#' back and forth between the main process and the workers, which removes the
#' dominant main-process serialization cost of the two-stage arrangement.
#' The per-batch closure captures only `config` and the batch's own metadata
#' rows, so (unlike the two-stage transform) `future.scheduling` chunking is
#' safe and keeps progress relaying steadily.
#' @param file_list_dt `data.frame`/`data.table` of file metadata with at
#'   least `file_path`, `file_name`, `yearbook`, and `commodity` columns.
#' @param config Named configuration list with `column_required`.
#' @param progressor Optional progress-reporting function; ticks once per file
#'   for the read and once per file for the transform, exactly like the
#'   two-stage path, so the `(2 * nfiles) + 4` import budget closes.
#' @return Named list with `transformed` (`list(wide_raw, long_raw)`
#'   satisfying the transform contract) and `errors` (character vector of
#'   read errors).
#' @examples
#' \dontrun{
#' read_transform_pipeline_files(file_list_dt, config)
#' }
read_transform_pipeline_files <- function(
  file_list_dt,
  config,
  progressor = NULL
) {
  assert_or_abort(checkmate::check_data_frame(file_list_dt, min.cols = 1))
  assert_or_abort(checkmate::check_names(
    names(file_list_dt),
    must.include = "file_path",
    what = "names(file_list_dt)"
  ))
  assert_or_abort(checkmate::check_character(
    file_list_dt$file_path,
    any.missing = FALSE,
    null.ok = TRUE
  ))
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))
  assert_or_abort(checkmate::check_character(
    config$column_required,
    any.missing = FALSE,
    min.len = 1
  ))
  if (!is.null(progressor)) {
    assert_or_abort(checkmate::check_function(progressor))
  }

  if (nrow(file_list_dt) == 0) {
    return(list(
      transformed = build_empty_transform_result(),
      errors = character(0)
    ))
  }

  file_list_dt <- ensure_data_table(file_list_dt)
  file_paths <- file_list_dt$file_path
  batch_size <- resolve_import_workbook_batch_size(config)
  workbook_batches <- split_workbook_batches(
    file_paths = file_paths,
    batch_size = batch_size
  )

  # Each batch carries its own metadata rows so workers receive only small
  # objects; batch order and within-batch file order preserve the global file
  # order, keeping the combined output identical to the two-stage path.
  batch_objects <- lapply(workbook_batches, function(batch_paths) {
    batch_indices <- match(batch_paths, file_paths)
    list(
      paths = batch_paths,
      file_rows = lapply(batch_indices, function(i) file_list_dt[i])
    )
  })

  use_parallel <- !inherits(future::plan(), "sequential") &&
    length(batch_objects) > 1L

  progress_messages <- get_pipeline_constants()$progress$messages$import
  read_message_template <- progress_messages$read_file
  transform_message_template <- progress_messages$transform_file

  fused_one_batch <- function(batch) {
    if (!is.null(progressor)) {
      for (file_path in batch$paths) {
        progressor(sprintf(read_message_template, fs::path_file(file_path)))
      }
    }

    batch_read <- read_workbook_batch(
      file_paths = batch$paths,
      config = config
    )

    transforms <- vector("list", length(batch$paths))
    for (k in seq_along(batch$paths)) {
      file_row <- batch$file_rows[[k]]

      if (!is.null(progressor)) {
        progressor(sprintf(
          transform_message_template,
          file_row[["file_name"]]
        ))
      }

      transforms[[k]] <- transform_single_file(
        file_row,
        batch_read$read_data_list[[k]],
        config
      )
    }

    return(list(transforms = transforms, errors = batch_read$errors))
  }

  if (use_parallel) {
    batch_results <- future.apply::future_lapply(
      batch_objects,
      fused_one_batch,
      future.seed = NULL,
      future.scheduling = resolve_import_future_scheduling(config)
    )
  } else {
    batch_results <- lapply(batch_objects, fused_one_batch)
  }

  results <- unlist(
    lapply(batch_results, `[[`, "transforms"),
    recursive = FALSE,
    use.names = FALSE
  )
  results <- Filter(Negate(is.null), results)

  errors <- unlist(
    lapply(batch_results, `[[`, "errors"),
    use.names = FALSE
  )
  if (is.null(errors)) {
    errors <- character(0)
  }

  transformed <- if (length(results) == 0) {
    build_empty_transform_result()
  } else {
    n_results <- length(results)
    wide_list <- vector("list", n_results)
    long_list <- vector("list", n_results)
    for (i in seq_len(n_results)) {
      wide_list[[i]] <- results[[i]][["wide_raw"]]
      long_list[[i]] <- results[[i]][["long_raw"]]
    }
    list(
      wide_raw = data.table::rbindlist(wide_list, use.names = TRUE, fill = TRUE),
      long_raw = data.table::rbindlist(long_list, use.names = TRUE, fill = TRUE)
    )
  }

  assert_transform_result_contract(transformed)

  return(list(transformed = transformed, errors = errors))
}

#' Transform a list of files and combine results
#' Processes all files, row-binds the wide and long outputs, and returns a
#' combined transformation result satisfying the transform contract.
#' @param file_list_dt `data.frame`/`data.table` of file metadata.
#' @param read_data_list List of `data.frame`s matching `file_list_dt` rows.
#' @param config Named configuration list.
#' @param progressor Optional progress-reporting function.
#' @return Named list with `wide_raw` and `long_raw` `data.table`s.
#' @examples
#' \dontrun{
#' transform_files_list(file_list_dt, read_data_list, config)
#' }
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
