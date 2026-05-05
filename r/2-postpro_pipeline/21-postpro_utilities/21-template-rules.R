write_stage_rule_template <- function(
  audit_paths,
  overwrite = TRUE
) {
  checkmate::assert_list(audit_paths, min.len = 1)
  checkmate::assert_string(audit_paths$templates_dir, min.chars = 1)
  checkmate::assert_flag(overwrite)

  template_columns <- get_canonical_rule_columns()
  template_data <- data.table::as.data.table(setNames(
    replicate(length(template_columns), character(0), simplify = FALSE),
    template_columns
  ))

  guidance_data <- data.table::data.table(
    note = c(
      "Fill all required columns.",
      "Column names must remain unchanged.",
      "Rows define conditional source-target replacements."
    )
  )

  template_path <- fs::path(
    audit_paths$templates_dir,
    get_pipeline_constants()$postpro$clean_harmonize_template_file_name
  )

  writexl::write_xlsx(
    list(clean_harmonize_template = template_data, guidance = guidance_data),
    path = template_path
  )

  return(template_path)
}

#' @title Generate post-processing rule templates
#' @description Writes a single unified rule template under
#' `audit_root_dir/templates`. Both clean and harmonize stages share the same
#' column schema; the only difference between rule files is the `clean_` or
#' `harmonize_` filename prefix.
#' @param config Named configuration list.
#' @param overwrite Logical scalar indicating whether existing templates are replaced.
#' @return Named character vector with `clean_harmonize_template` path.
#' @importFrom checkmate assert_list assert_flag
generate_postpro_rule_templates <- function(config, overwrite = TRUE) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_flag(overwrite)

  audit_paths <- initialize_postpro_output_root(config)

  template_path <- write_stage_rule_template(
    audit_paths = audit_paths,
    overwrite = overwrite
  )

  return(c(clean_harmonize_template = template_path))
}

#' @title Read rule table from csv or excel
#' @description Reads a rule table file and returns a `data.table`. For
#' Excel files, all worksheets whose columns match the canonical rule schema
#' (with optional `clean_`/`harmonize_` prefixes) are read and row-bound in
#' workbook order.
#' @param file_path Character scalar path to rule file.
#' @return `data.table` containing rule rows.
#' @importFrom checkmate assert_string assert_file_exists
#' @importFrom fs path_ext
#' @importFrom readr read_csv
#' @importFrom readxl read_excel excel_sheets
#' @examples
#' \dontrun{read_rule_table("data/1-import/11-clean_import/clean_rules.xlsx")}
read_rule_table <- function(file_path) {
  checkmate::assert_string(file_path, min.chars = 1)
  checkmate::assert_file_exists(file_path)

  file_extension <- fs::path_ext(file_path) |>
    tolower()

  if (identical(file_extension, "csv")) {
    return(
      readr::read_csv(file_path, show_col_types = FALSE) |>
        data.table::as.data.table()
    )
  }

  if (file_extension %in% c("xlsx", "xls")) {
    canonical_columns <- get_canonical_rule_columns()
    optional_columns <- c("value_source")
    required_columns <- setdiff(canonical_columns, optional_columns)
    stage_prefix_pattern <- "^(clean|harmonize)_"

    sheet_names <- readxl::excel_sheets(file_path)

    sheet_results <- lapply(sheet_names, function(sheet_name) {
      sheet_dt <- readxl::read_excel(file_path, sheet = sheet_name) |>
        data.table::as.data.table()

      available_columns <- colnames(sheet_dt)
      normalize_columns <- sub(stage_prefix_pattern, "", available_columns)

      has_duplicated_normalize <- anyDuplicated(normalize_columns) > 0L
      has_unexpected_columns <- any(!(normalize_columns %in% canonical_columns))
      has_required_columns <- all(required_columns %in% normalize_columns)

      is_matching_sheet <-
        !has_duplicated_normalize &&
        !has_unexpected_columns &&
        has_required_columns

      if (is_matching_sheet) {
        data.table::setnames(sheet_dt, available_columns, normalize_columns)
      }

      return(list(
        matches = is_matching_sheet,
        rules_dt = sheet_dt
      ))
    })

    matching_sheet_indexes <- which(vapply(
      sheet_results,
      function(result) {
        isTRUE(result$matches)
      },
      logical(1)
    ))

    if (length(matching_sheet_indexes) == 0L) {
      cli::cli_abort(c(
        "No worksheets with matching rule columns found in {.file {file_path}}.",
        "x" = paste0(
          "Required columns: ",
          paste(required_columns, collapse = ", ")
        ),
        "x" = paste0("Available sheets: ", paste(sheet_names, collapse = ", "))
      ))
    }

    matching_tables <- lapply(
      sheet_results[matching_sheet_indexes],
      function(result) {
        result$rules_dt
      }
    )

    return(data.table::rbindlist(
      matching_tables,
      use.names = TRUE,
      fill = TRUE
    ))
  }

  cli::cli_abort("Unsupported rule extension for {.file {file_path}}.")
}

#' @title Load stage rule payloads
#' @description Discovers stage-specific rule files and returns deterministic payloads.
#' @param config Named configuration list.
#' @param stage_name Character scalar stage label (`clean` or `harmonize`).
#' @return List of payloads with `rule_file_id` and `raw_rules`.
#' @importFrom checkmate assert_list assert_string
#' @importFrom fs dir_ls dir_create path_file
#' @importFrom purrr map
load_stage_rule_payloads <- function(config, stage_name) {
  checkmate::assert_list(config, min.len = 1)
  validated_stage_name <- validate_postpro_stage_name(stage_name)

  import_dir <- switch(
    validated_stage_name,
    clean = config$paths$data$import$cleaning,
    harmonize = config$paths$data$import$harmonization
  )
  checkmate::assert_string(import_dir, min.chars = 1)

  ensure_directories_exist(import_dir, recurse = TRUE)

  stage_pattern <- switch(
    validated_stage_name,
    clean = "^clean_.*\\.(xlsx|xls|csv)$",
    harmonize = "^harmonize_.*\\.(xlsx|xls|csv)$"
  )

  available_files <- fs::dir_ls(
    path = import_dir,
    regexp = "\\.(xlsx|xls|csv)$",
    type = "file"
  )

  ordered_files <- available_files[
    grepl(stage_pattern, basename(available_files))
  ] |>
    sort()

  payloads <- purrr::map(ordered_files, function(file_path) {
    list(
      rule_file_id = fs::path_file(file_path),
      rule_file_path = normalizePath(
        file_path,
        winslash = "/",
        mustWork = FALSE
      ),
      raw_rules = read_rule_table(file_path)
    )
  })

  return(payloads)
}

#' @title Resolve stage runtime cache settings
#' @description Resolves runtime cache settings from centralized defaults with
#' optional configuration overrides.
#' @param config Named configuration list.
#' @return Named list with `enabled`, `cache_file_name`, and `max_entries`.
#' @importFrom checkmate assert_list assert_flag assert_string assert_int
