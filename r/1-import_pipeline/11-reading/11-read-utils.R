# read utilities for import pipeline
build_read_error <- function(context_message, file_path, details) {
  return(cli::format_error(c(
    "{context_message} {.file {fs::path_file(file_path)}}.",
    "x" = details
  )))
}

safe_execute_read <- function(operation, context_message, file_path) {
  assert_or_abort(checkmate::check_function(operation))
  assert_or_abort(checkmate::check_string(context_message, min.chars = 1))
  assert_or_abort(checkmate::check_string(file_path, min.chars = 1))

  return(tryCatch(
    list(result = operation(), errors = character(0)),
    error = function(condition) {
      list(
        result = NULL,
        errors = build_read_error(context_message, file_path, condition$message)
      )
    }
  ))
}

create_empty_read_result <- function(errors = character(0)) {
  return(list(data = data.table::data.table(), errors = errors))
}

has_read_errors <- function(read_result) {
  return(!is.null(read_result$errors) && length(read_result$errors) > 0)
}

assert_read_result_contract <- function(read_result) {
  assert_or_abort(checkmate::check_list(
    read_result,
    min.len = 1,
    any.missing = FALSE
  ))
  assert_or_abort(checkmate::check_data_frame(read_result$data, min.rows = 0))
  assert_or_abort(checkmate::check_character(
    read_result$errors,
    any.missing = FALSE
  ))

  return(invisible(TRUE))
}

normalize_pipeline_read_result <- function(read_result) {
  assert_or_abort(checkmate::check_list(read_result, min.len = 1))

  if (is.null(read_result$result)) {
    return(list(
      data = create_empty_read_result()$data,
      errors = c(read_result$errors)
    ))
  }

  assert_read_result_contract(read_result$result)

  return(list(
    data = data.table::setDT(read_result$result$data),
    errors = c(read_result$errors, read_result$result$errors)
  ))
}
