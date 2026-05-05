# batching and pipeline-level reading
split_workbook_batches <- function(file_paths, batch_size) {
  assert_or_abort(checkmate::check_character(
    file_paths,
    any.missing = FALSE,
    null.ok = TRUE
  ))
  assert_or_abort(checkmate::check_int(batch_size, lower = 1L))

  if (length(file_paths) == 0L) {
    return(list())
  }

  batch_index <- ceiling(seq_along(file_paths) / as.integer(batch_size))

  return(split(file_paths, batch_index))
}

resolve_import_workbook_batch_size <- function(config) {
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))

  default_batch_size <- get_pipeline_constants()$performance$import_workbook_batch_size
  resolved_batch_size <- default_batch_size

  if (
    is.list(config$performance) &&
      !is.null(config$performance$import_workbook_batch_size)
  ) {
    resolved_batch_size <- config$performance$import_workbook_batch_size
  }

  suppressWarnings(resolved_batch_size <- as.integer(resolved_batch_size))
  assert_or_abort(checkmate::check_int(resolved_batch_size, lower = 1L))

  return(resolved_batch_size)
}

read_workbook_batch <- function(
  file_paths,
  config,
  sheet_names_by_file = NULL
) {
  assert_or_abort(checkmate::check_character(
    file_paths,
    any.missing = FALSE,
    null.ok = TRUE
  ))
  assert_or_abort(checkmate::check_list(config, any.missing = FALSE))
  assert_or_abort(checkmate::check_character(
    config$column_required,
    any.missing = FALSE,
    min.len = 1
  ))

  if (!is.null(sheet_names_by_file)) {
    assert_or_abort(checkmate::check_list(
      sheet_names_by_file,
      names = "named",
      any.missing = TRUE
    ))
  }

  if (length(file_paths) == 0L) {
    return(list(read_data_list = list(), errors = character(0)))
  }

  unique_file_paths <- unique(file_paths)

  unique_results <- lapply(unique_file_paths, function(file_path) {
    mapped_sheet_names <- NULL

    if (
      !is.null(sheet_names_by_file) && file_path %in% names(sheet_names_by_file)
    ) {
      mapped_sheet_names <- sheet_names_by_file[[file_path]]

      if (!is.null(mapped_sheet_names)) {
        assert_or_abort(checkmate::check_character(
          mapped_sheet_names,
          any.missing = FALSE
        ))
      }
    }

    safe_read_result <- safe_execute_read(
      operation = \() {
        read_file_sheets(
          file_path = file_path,
          config = config,
          sheet_names = mapped_sheet_names
        )
      },
      context_message = "failed to read workbook in batch",
      file_path = file_path
    )

    normalize_pipeline_read_result(safe_read_result)
  })

  names(unique_results) <- unique_file_paths

  read_data_list <- lapply(file_paths, function(file_path) {
    data.table::copy(unique_results[[file_path]]$data)
  })

  errors <- unlist(
    lapply(file_paths, function(file_path) {
      unique_results[[file_path]]$errors
    }),
    use.names = FALSE
  )

  return(list(read_data_list = read_data_list, errors = errors))
}

read_pipeline_files <- function(file_list_dt, config, progressor = NULL) {
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

  if (!is.null(progressor)) {
    assert_or_abort(checkmate::check_function(progressor))
  }
  assert_or_abort(checkmate::check_character(
    config$column_required,
    any.missing = FALSE,
    min.len = 1
  ))

  if (nrow(file_list_dt) == 0) {
    return(list(read_data_list = list(), errors = character(0)))
  }

  file_paths <- file_list_dt$file_path
  batch_size <- resolve_import_workbook_batch_size(config)
  workbook_batches <- split_workbook_batches(
    file_paths = file_paths,
    batch_size = batch_size
  )

  use_parallel <- !inherits(future::plan(), "sequential") &&
    length(workbook_batches) > 1L

  if (use_parallel) {
    batch_results <- future.apply::future_lapply(
      workbook_batches,
      function(batch_paths) {
        read_workbook_batch(
          file_paths = batch_paths,
          config = config
        )
      },
      future.seed = NULL
    )
  } else {
    batch_results <- lapply(
      workbook_batches,
      function(batch_paths) {
        if (!is.null(progressor)) {
          lapply(batch_paths, function(file_path) {
            progressor(sprintf(
              "Import Pipeline Progress: reading %s",
              fs::path_file(file_path)
            ))
          })
        }

        read_workbook_batch(
          file_paths = batch_paths,
          config = config
        )
      }
    )
  }

  batch_read_lists <- lapply(batch_results, `[[`, "read_data_list")
  batch_error_lists <- lapply(batch_results, `[[`, "errors")

  read_data_list <- if (length(batch_read_lists) > 0L) {
    unlist(batch_read_lists, recursive = FALSE, use.names = FALSE)
  } else {
    list()
  }

  errors <- if (length(batch_error_lists) > 0L) {
    unlist(batch_error_lists, use.names = FALSE)
  } else {
    character(0)
  }

  return(list(
    read_data_list = read_data_list,
    errors = errors
  ))
}
