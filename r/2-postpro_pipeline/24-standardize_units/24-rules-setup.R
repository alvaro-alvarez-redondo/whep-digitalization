# script: units standardization stage functions
# description: validate and apply numeric unit conversions and run numeric standardization.

#' @title Validate required rule-table columns
#' @description Validates presence and non-missingness of required columns.
#' @param rule_dt Data.frame/data.table containing rule rows.
#' @param required_columns Character vector of required column names.
#' @param rule_label Character scalar label used in error messages.
#' @return Invisibly returns `TRUE`.
#' @importFrom checkmate assert_data_frame assert_character assert_string
validate_rule_schema <- function(rule_dt, required_columns, rule_label) {
  checkmate::assert_data_frame(rule_dt, min.rows = 1)
  checkmate::assert_character(
    required_columns,
    min.len = 1,
    any.missing = FALSE
  )
  checkmate::assert_string(rule_label, min.chars = 1)

  missing_columns <- setdiff(required_columns, names(rule_dt))
  if (length(missing_columns) > 0L) {
    cli::cli_abort(c(
      "Missing required columns in {.val {rule_label}} rules.",
      "x" = paste(missing_columns, collapse = ", ")
    ))
  }

  columns_with_na <- required_columns[vapply(
    required_columns,
    function(column_name) {
      anyNA(rule_dt[[column_name]])
    },
    logical(1)
  )]

  if (length(columns_with_na) > 0L) {
    cli::cli_abort(c(
      "Found missing values in required {.val {rule_label}} rule columns.",
      "x" = paste(columns_with_na, collapse = ", ")
    ))
  }

  return(invisible(TRUE))
}

#' @title Normalize conversion rule columns
#' @description Renames legacy conversion rule columns to cohesive internal names
#' (`commodity_key`, `unit_source`, `unit_target`, `unit_factor`,
#' `unit_offset`) while preserving
#' backward compatibility for input files using legacy headers.
#' @param conversion_dt conversion rules data.table/data.frame.
#' @return data.table with normalize internal column names.
#' @importFrom checkmate assert_data_frame
normalize_conversion_rule_columns <- function(conversion_dt) {
  checkmate::assert_data_frame(conversion_dt, min.rows = 0)

  normalize_conversion_dt <- data.table::copy(data.table::as.data.table(
    conversion_dt
  ))

  rename_mapping <- c(
    commodity = "commodity_key",
    source_unit = "unit_source",
    target_unit = "unit_target",
    multiplier = "unit_factor",
    addend = "unit_offset",
    from_unit = "unit_source",
    to_unit = "unit_target",
    factor = "unit_factor",
    offset = "unit_offset"
  )

  legacy_names <- names(rename_mapping)
  available_legacy <- legacy_names[
    legacy_names %in% names(normalize_conversion_dt)
  ]

  if (length(available_legacy) > 0L) {
    target_names <- unname(rename_mapping[available_legacy])
    rename_mask <- !target_names %in% names(normalize_conversion_dt)

    if (any(rename_mask)) {
      data.table::setnames(
        normalize_conversion_dt,
        old = available_legacy[rename_mask],
        new = target_names[rename_mask]
      )
    }
  }

  return(normalize_conversion_dt)
}

#' @title Ensure standardize-units template exists
#' @description Creates `data/2-postpro/templates` when
#' missing and initializes `standardize_units_template.xlsx` with required
#' columns when absent.
#' @param config Named configuration list.
#' @return Character scalar template file path.
#' @importFrom checkmate assert_list assert_string assert_directory_exists
#' @importFrom fs path
#' @importFrom writexl write_xlsx
#' @examples
#' \dontrun{ensure_standardize_template_exists(config)}
ensure_standardize_template_exists <- function(config) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(
    config$paths$data$audit$templates_dir,
    min.chars = 1
  )

  templates_dir <- config$paths$data$audit$templates_dir

  ensure_directories_exist(templates_dir, recurse = TRUE)
  checkmate::assert_directory_exists(templates_dir)

  template_path <- fs::path(
    templates_dir,
    get_pipeline_constants()$postpro$standardize_units_template_file_name
  )

  if (!file.exists(template_path)) {
    template_dt <- data.table::data.table(
      commodity_key = character(0),
      unit_source = character(0),
      unit_target = character(0),
      unit_factor = numeric(0),
      unit_offset = numeric(0)
    )

    writexl::write_xlsx(
      list(units_standardization = template_dt),
      path = template_path
    )
  }

  return(template_path)
}

#' @title Read one standardization workbook
#' @description Reads all worksheet tabs in a standardization workbook except
#' explicitly excluded sheet names (for example `master_unit`), normalizes
#' column names, and keeps only sheets that contain required standardization
#' rule columns.
#' @param rule_path Character scalar path to one workbook.
#' @param excluded_sheet_names Character vector of sheet names to skip.
#' @return `data.table` with standardized rule rows.
#' @importFrom checkmate assert_string assert_character assert_file_exists
#' @importFrom readxl excel_sheets read_excel
read_standardize_rule_workbook <- function(
  rule_path,
  excluded_sheet_names = character(0)
) {
  checkmate::assert_string(rule_path, min.chars = 1)
  checkmate::assert_file_exists(rule_path)
  checkmate::assert_character(excluded_sheet_names, any.missing = FALSE)

  required_columns <- c(
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset"
  )

  workbook_sheet_names <- readxl::excel_sheets(rule_path)
  normalize_excluded <- normalize_string(excluded_sheet_names)

  selected_sheet_names <- workbook_sheet_names[
    !(normalize_string(workbook_sheet_names) %in% normalize_excluded)
  ]

  if (length(selected_sheet_names) == 0L) {
    cli::cli_abort(c(
      "No worksheets available for standardization after exclusions.",
      "x" = "file: {.file {rule_path}}",
      "x" = paste0(
        "excluded sheets: ",
        paste(excluded_sheet_names, collapse = ", ")
      ),
      "x" = paste0(
        "available sheets: ",
        paste(workbook_sheet_names, collapse = ", ")
      )
    ))
  }

  matched_sheet_tables <- lapply(selected_sheet_names, function(sheet_name) {
    sheet_dt <- readxl::read_excel(rule_path, sheet = sheet_name) |>
      data.table::as.data.table()

    sheet_dt <- normalize_conversion_rule_columns(sheet_dt)

    if (!all(required_columns %in% colnames(sheet_dt))) {
      return(NULL)
    }

    return(sheet_dt[, ..required_columns])
  })

  matched_sheet_indexes <- which(vapply(
    matched_sheet_tables,
    function(sheet_dt) {
      !is.null(sheet_dt)
    },
    logical(1)
  ))

  if (length(matched_sheet_indexes) == 0L) {
    cli::cli_abort(c(
      "No worksheets with matching standardization columns found.",
      "x" = "file: {.file {rule_path}}",
      "x" = paste0(
        "required columns: ",
        paste(required_columns, collapse = ", ")
      ),
      "x" = paste0(
        "selected sheets: ",
        paste(selected_sheet_names, collapse = ", ")
      )
    ))
  }

  matched_sheet_names <- selected_sheet_names[matched_sheet_indexes]
  matched_sheet_list <- matched_sheet_tables[matched_sheet_indexes]
  names(matched_sheet_list) <- matched_sheet_names

  return(data.table::rbindlist(
    matched_sheet_list,
    use.names = TRUE,
    fill = TRUE,
    idcol = "source_rule_sheet"
  ))
}

#' @title Read all standardize rule Excel files
#' @description Discovers all Excel files in
#' `config$paths$data$import$standardization` and reads each file
#' independently.
#' @param config named configuration list.
#' @return named list with `rules` and `source_paths`.
#' @importFrom checkmate assert_list assert_string assert_directory_exists
#'  dir_ls path_file
#' @examples
#' \dontrun{read_all_standardize_rule_files(config)}
read_all_standardize_rule_files <- function(config) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_string(
    config$paths$data$import$standardization,
    min.chars = 1
  )

  excluded_sheet_names <-
    get_pipeline_constants()$postpro$standardization$excluded_sheet_names
  checkmate::assert_character(excluded_sheet_names, any.missing = FALSE)

  standardization_dir <- config$paths$data$import$standardization
  ensure_directories_exist(standardization_dir, recurse = TRUE)
  checkmate::assert_directory_exists(standardization_dir)

  rule_paths <- fs::dir_ls(
    path = standardization_dir,
    regexp = "\\.(xlsx|xls)$",
    type = "file"
  ) |>
    sort()

  if (length(rule_paths) == 0L) {
    return(list(
      rules = data.table::data.table(),
      source_paths = character(0)
    ))
  }

  rules_by_file <- lapply(rule_paths, function(rule_path) {
    tryCatch(
      {
        file_rules_dt <- read_standardize_rule_workbook(
          rule_path = rule_path,
          excluded_sheet_names = excluded_sheet_names
        )
        file_rules_dt[, source_rule_file := fs::path_file(rule_path)]

        return(file_rules_dt)
      },
      error = function(error_condition) {
        cli::cli_abort(c(
          "invalid standardization rule file.",
          "x" = "file: {.file {rule_path}}",
          "x" = error_condition$message
        ))
      }
    )
  })

  combined_rules <- data.table::rbindlist(
    rules_by_file,
    use.names = TRUE,
    fill = TRUE
  )

  return(list(
    rules = combined_rules,
    source_paths = rule_paths
  ))
}

#' @title Validate conversion rules
#' @description Validates numeric conversion-rule schema, uniqueness, and
#' deterministic idempotency constraints.
#' @param conversion_dt conversion rules data.table/data.frame.
#' @return Invisibly returns `TRUE`.
#' @importFrom checkmate assert_data_frame
#' @examples
#' \dontrun{validate_conversion_rules(conversion_dt)}
validate_conversion_rules <- function(conversion_dt) {
  checkmate::assert_data_frame(conversion_dt, min.rows = 1)

  required_columns <- c(
    "commodity_key",
    "unit_source",
    "unit_target",
    "unit_factor",
    "unit_offset"
  )
  validate_rule_schema(
    conversion_dt,
    required_columns,
    "standardization conversion"
  )

  duplicate_rows <- conversion_dt[, .N, by = .(commodity_key, unit_source)][
    N > 1L
  ]
  if (nrow(duplicate_rows) > 0L) {
    cli::cli_abort(
      "conversion rules contain duplicate {.val (commodity_key, unit_source)} definitions"
    )
  }

  unit_factor_num <- suppressWarnings(as.numeric(
    conversion_dt$unit_factor
  ))
  unit_offset_num <- suppressWarnings(as.numeric(conversion_dt$unit_offset))

  if (any(!is.finite(unit_factor_num))) {
    cli::cli_abort("conversion unit_factor values must be finite")
  }

  if (any(!is.finite(unit_offset_num))) {
    cli::cli_abort("conversion unit_offset values must be finite")
  }

  source_pairs <- unique(data.table::data.table(
    commodity_match_key = normalize_string(conversion_dt$commodity_key),
    unit_match_key = normalize_string(conversion_dt$unit_source)
  ))
  target_pairs <- unique(data.table::data.table(
    commodity_match_key = normalize_string(conversion_dt$commodity_key),
    unit_match_key = normalize_string(conversion_dt$unit_target)
  ))

  # Exclude "all commodity" from chained rule detection since it serves as fallback
  source_pairs_specific <- source_pairs[commodity_match_key != "all commodity"]
  target_pairs_specific <- target_pairs[commodity_match_key != "all commodity"]

  data.table::setkey(source_pairs_specific, commodity_match_key, unit_match_key)
  data.table::setkey(target_pairs_specific, commodity_match_key, unit_match_key)

  chained_rules <- source_pairs_specific[target_pairs_specific, nomatch = 0L]

  if (nrow(chained_rules) > 0L) {
    cli::cli_abort(
      "conversion rules create chained conversions for the same commodity; this can trigger double conversion on repeated runs"
    )
  }

  return(invisible(TRUE))
}

#' @title Prepare standardization rules
#' @description Normalizes headers, validates merged rules, and materializes
#' numeric and key columns used for conversion joins.
#' @param raw_rules_dt conversion rules data.table/data.frame.
#' @return Prepared `data.table` suitable for conversion joins.
#' @importFrom checkmate assert_data_frame
prepare_standardize_rules <- function(raw_rules_dt) {
  checkmate::assert_data_frame(raw_rules_dt, min.rows = 0)

  prepared_rules_dt <- normalize_conversion_rule_columns(raw_rules_dt)

  if (nrow(prepared_rules_dt) == 0L) {
    return(prepared_rules_dt)
  }

  validate_conversion_rules(prepared_rules_dt)

  prepared_rules_dt[, unit_factor_num := as.numeric(unit_factor)]
  prepared_rules_dt[, unit_offset_num := as.numeric(unit_offset)]
  prepared_rules_dt[, commodity_match_key := normalize_string(commodity_key)]
  prepared_rules_dt[, unit_source_key := normalize_string(unit_source)]

  data.table::setkey(prepared_rules_dt, commodity_match_key, unit_source_key)

  return(prepared_rules_dt)
}

#' @title Apply prepared standardization rules
#' @description Applies prepared conversion rules to dataset values using keyed
#' vectorized joins with fallback to "all commodity" rules. Conversion lookup
#' occurs in two stages: (1) match on specific (commodity, unit_source), and (2)
#' if no match found, attempt match on ("all commodity", unit_source). This
#' allows general conversions to apply to all commodity unless overridden by
#' commodity-specific rules.
#' @param mapped_dt data.table/data.frame to standardize.
#' @param prepared_rules_dt Prepared rule table from `prepare_standardize_rules()`.
#' @param unit_column character scalar unit column name.
#' @param value_column character scalar numeric value column name.
#' @param commodity_column character scalar commodity column name.
#' @return named list with `data`, `matched_count`, `unmatched_count`, and
#' `matched_rule_counts`.
#' @importFrom checkmate assert_data_frame assert_string
