audit_character_non_empty <- function(dataset_dt, column_name) {
  assert_or_abort(checkmate::check_data_frame(dataset_dt, min.rows = 0))
  assert_or_abort(checkmate::check_string(column_name, min.chars = 1))
  assert_or_abort(checkmate::check_names(
    names(dataset_dt),
    must.include = column_name
  ))

  values <- dataset_dt[[column_name]]
  invalid_rows <- which(is.na(values) | !nzchar(trimws(values)))

  if (length(invalid_rows) == 0) {
    return(empty_audit_findings_dt())
  }

  return(data.table::data.table(
    row_index = invalid_rows,
    audit_column = column_name,
    audit_type = "character_non_empty",
    audit_message = "value must be a non-empty character string"
  ))
}

#' @title audit numeric string values
#' @description validate numeric string pattern.
#' @param dataset_dt data frame.
#' @param column_name character scalar.
#' @return data.table of findings.
#' @examples
#' dataset_dt <- data.frame(value = c("10", "bad"), stringsAsFactors = FALSE)
#' audit_numeric_string(dataset_dt, "value")
#' @export
audit_numeric_string <- function(dataset_dt, column_name = "value") {
  assert_or_abort(checkmate::check_data_frame(dataset_dt, min.rows = 0))
  assert_or_abort(checkmate::check_string(column_name, min.chars = 1))
  assert_or_abort(checkmate::check_names(
    names(dataset_dt),
    must.include = column_name
  ))

  values <- as.character(dataset_dt[[column_name]])
  invalid_rows <- which(!is.na(values) & !grepl("^[0-9]+(\\.[0-9]+)?$", values))

  if (length(invalid_rows) == 0) {
    return(empty_audit_findings_dt())
  }

  return(data.table::data.table(
    row_index = invalid_rows,
    audit_column = column_name,
    audit_type = "numeric_string",
    audit_message = "value must contain only digits and at most one decimal point"
  ))
}

#' @title build audit validation plan
#' @description convert a named mapping of audit types and columns into a
#' two-column plan table with one row per audit-type/column combination.
#' @param audit_columns_by_type named list that maps audit types to character
#' vectors of column names.
#' @param supported character vector of supported audit types.
#' @return data.table with columns `audit_type` and `column_name`.
#' @importFrom checkmate check_list check_character
#' @importFrom cli cli_abort
#' @importFrom data.table data.table
#' @examples
#' build_audit_validation_plan(list(character_non_empty = c("document")), "character_non_empty")
#' @export
build_audit_validation_plan <- function(audit_columns_by_type, supported) {
  assert_or_abort(checkmate::check_list(audit_columns_by_type, min.len = 1))
  assert_or_abort(checkmate::check_character(
    supported,
    min.len = 1,
    any.missing = FALSE
  ))

  supported_columns <- audit_columns_by_type[supported]

  valid_columns <- vapply(
    supported_columns,
    function(column_names) {
      isTRUE(checkmate::check_character(
        column_names,
        min.len = 1,
        any.missing = FALSE
      ))
    },
    logical(1)
  )

  if (!all(valid_columns)) {
    cli::cli_abort(
      "each supported audit type must map to a non-empty character vector of columns"
    )
  }

  audit_type_vector <- rep(supported, times = lengths(supported_columns))
  column_name_vector <- unlist(supported_columns, use.names = FALSE)

  return(data.table::data.table(
    audit_type = audit_type_vector,
    column_name = column_name_vector
  ))
}

#' @title run master validation
#' @description execute configured validators.
#' @param dataset_dt data frame.
#' @param audit_columns_by_type named list.
#' @param selected_validations optional character vector of validation types to execute.
#' when `NULL`, all supported validation types from `audit_columns_by_type` are executed.
#' @return named list with findings and invalid_row_index.
#' @importFrom checkmate check_data_frame check_list check_character
#' @importFrom data.table data.table rbindlist
#' @importFrom purrr map2
#' @importFrom cli cli_warn
#' @examples
#' dataset_dt <- data.frame(document = c("ok.xlsx", ""), value = c("10", "bad"))
#' audit_map <- list(character_non_empty = "document", numeric_string = "value")
#' run_master_validation(dataset_dt, audit_map)
#' @export
run_master_validation <- function(
  dataset_dt,
  audit_columns_by_type,
  selected_validations = NULL
) {
  assert_or_abort(checkmate::check_data_frame(dataset_dt, min.rows = 0))
  assert_or_abort(checkmate::check_list(audit_columns_by_type, min.len = 1))

  registry <- list(
    character_non_empty = audit_character_non_empty,
    numeric_string = audit_numeric_string
  )
  stopifnot(is.list(registry))

  if (!is.null(selected_validations)) {
    assert_or_abort(checkmate::check_character(
      selected_validations,
      min.len = 1,
      any.missing = FALSE
    ))
  }

  audit_types <- names(audit_columns_by_type)
  supported <- intersect(audit_types, names(registry))
  unsupported <- setdiff(audit_types, names(registry))

  if (length(unsupported) > 0) {
    cli::cli_warn(c(
      "unsupported audit types were skipped",
      "i" = "unsupported types: {toString(unsupported)}"
    ))
  }

  if (!is.null(selected_validations)) {
    supported <- intersect(supported, unique(selected_validations))
  }

  if (length(supported) == 0) {
    findings_dt <- empty_audit_findings_dt()
    return(list(
      findings = findings_dt,
      invalid_row_index = integer(0)
    ))
  }

  validation_plan <- build_audit_validation_plan(
    audit_columns_by_type = audit_columns_by_type,
    supported = supported
  )

  findings <- purrr::map2(
    validation_plan$audit_type,
    validation_plan$column_name,
    \(audit_type, column_name) registry[[audit_type]](dataset_dt, column_name)
  )

  findings_dt <- data.table::rbindlist(findings, fill = TRUE)
  if (nrow(findings_dt) == 0) {
    findings_dt <- empty_audit_findings_dt()
  }

  return(list(
    findings = findings_dt,
    invalid_row_index = sort(unique(findings_dt$row_index))
  ))
}

#' @title resolve audit columns by validation type
#' @description return audit columns grouped by validator type. if
#' config$audit_columns_by_type is present, it is returned. otherwise,
#' a default mapping is created from config$audit_columns and config$column_order.
#' @param config named list with audit configuration.
#' @return named list mapping audit types to column names.
#' @examples
#' resolve_audit_columns_by_type(config)
#' @export
resolve_audit_columns_by_type <- function(config) {
  assert_or_abort(checkmate::check_list(
    config,
    min.len = 1,
    any.missing = FALSE
  ))

  load_audit_config(config)

  if (!is.null(config$audit_columns_by_type)) {
    audit_columns_by_type <- config$audit_columns_by_type
  } else {
    audit_columns_by_type <- list(
      character_non_empty = unique(config$audit_columns),
      numeric_string = intersect("value", config$column_order)
    )
  }

  return(audit_columns_by_type)
}

#' @title export validation audit report
#' @description write audit results to an excel workbook at output_path.
#' Only creates folders and workbook if there is data to export.
#' Output is sorted by document and written to sheet audit_report
#' with specific cells highlighted based on config styles.
#' @param audit_dt data frame or data table containing at least document.
#' @param config named audit configuration list containing export styles.
#' @param findings_dt data table with row_index and audit_column.
#' @param output_path character scalar destination path for the excel file.
#' @return character scalar with written output path (or NULL if nothing written).
#' @examples
#' \dontrun{
#' audit_dt <- data.frame(document = "a.xlsx", stringsAsFactors = FALSE)
#' config <- list(
#'   column_order = c("document"),
#'   audit_columns = c("document"),
#'   paths = list(
#'     data = list(
#'       import = list(raw = tempdir()),
#'       audit = list(
#'         audit_file_path = fs::path(tempdir(), "audit.xlsx")
#'       )
#'     )
#'   ),
#'   export_config = list(styles = list(error_highlight = list(fgFill = "#FFC7CE")))
#' )
#' export_validation_audit_report(audit_dt, config)
#' }
#' @export
