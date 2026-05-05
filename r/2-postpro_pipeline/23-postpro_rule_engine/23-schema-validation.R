# script: post-processing rule engine
# description: schema coercion, canonical rule validation, dictionary
# construction, vectorized matching/mutation engine, and rule payload
# application for the clean and harmonize post-processing stages.

#' @title Coerce rule schema to canonical columns
#' @description Enforces strict unified canonical schema. Strips the stage
#' prefix (e.g. `clean_` or `harmonize_`) from column names and validates
#' that the resulting columns match the canonical set.
#' @param rule_dt Rule table as data.frame/data.table.
#' @param stage_name Character scalar execution stage label.
#' @param rule_file_id Character scalar rule file identifier.
#' @return Canonicalized `data.table` rule table.
#' @importFrom checkmate assert_data_frame assert_string
coerce_rule_schema <- function(rule_dt, stage_name, rule_file_id) {
  checkmate::assert_data_frame(rule_dt, min.rows = 0)
  validated_stage_name <- validate_postpro_stage_name(stage_name)
  checkmate::assert_string(rule_file_id, min.chars = 1)

  canonical_columns <- get_canonical_rule_columns()
  stage_prefix <- paste0("^", validated_stage_name, "_")

  canonical_dt <- data.table::as.data.table(rule_dt)
  available_columns <- colnames(canonical_dt)

  normalize_columns <- sub(stage_prefix, "", available_columns)
  duplicated_normalize_columns <- normalize_columns[duplicated(
    normalize_columns
  )]

  if (length(duplicated_normalize_columns) > 0L) {
    cli::cli_abort(c(
      "Rule file {.file {rule_file_id}} contains duplicate columns after stage-prefix normalization.",
      "x" = paste(unique(duplicated_normalize_columns), collapse = ", ")
    ))
  }

  data.table::setnames(canonical_dt, available_columns, normalize_columns)
  available_columns <- colnames(canonical_dt)

  source_result_column <- get_stage_source_value_column(validated_stage_name)
  source_value_column_present <- source_result_column %in% available_columns
  optional_columns <- source_result_column

  missing_columns <- setdiff(canonical_columns, available_columns)
  missing_required_columns <- setdiff(missing_columns, optional_columns)

  if (length(missing_required_columns) > 0L) {
    cli::cli_abort(c(
      "Rule file {.file {rule_file_id}} is missing required columns.",
      "x" = paste(missing_required_columns, collapse = ", ")
    ))
  }

  unexpected_columns <- setdiff(available_columns, canonical_columns)
  if (length(unexpected_columns) > 0L) {
    cli::cli_abort(c(
      "Rule file {.file {rule_file_id}} contains unexpected columns.",
      "x" = paste(unexpected_columns, collapse = ", ")
    ))
  }

  if (!(source_result_column %in% colnames(canonical_dt))) {
    canonical_dt[, (source_result_column) := NA_character_]
  }

  canonical_dt <- canonical_dt[, ..canonical_columns]
  canonical_dt[, source_value_column_present := source_value_column_present]

  return(canonical_dt)
}

#' @title Normalize permitted missing rule values for internal validation
#' @description Converts allowed missing values in conditional rule value fields
#' to an internal placeholder used only during validation joins/grouping, while
#' preserving original rule semantics for downstream application.
#' @param rules_dt Canonical rule table.
#' @param stage_name Character scalar stage label.
#' @param na_placeholder Character scalar internal placeholder token.
#' @return Named list with `rules_for_validation` and `allowed_na_columns`.
#' @importFrom checkmate assert_data_frame assert_string
normalize_rule_values_for_validation <- function(
  rules_dt,
  stage_name,
  na_placeholder = get_pipeline_constants()$na_placeholder
) {
  checkmate::assert_data_frame(rules_dt, min.rows = 0)
  validate_postpro_stage_name(stage_name)
  checkmate::assert_string(na_placeholder, min.chars = 1)

  allowed_na_columns <- intersect(
    c(
      "value_source_raw",
      "value_source",
      "value_target_raw",
      "value_target"
    ),
    colnames(rules_dt)
  )

  rules_for_validation <- data.table::copy(data.table::as.data.table(rules_dt))

  if (length(allowed_na_columns) > 0L) {
    rules_for_validation[,
      (allowed_na_columns) := lapply(.SD, function(column_values) {
        replacement_values <- column_values

        if (is.character(replacement_values)) {
          replacement_values[trimws(replacement_values) == ""] <- na_placeholder
          replacement_values[is.na(replacement_values)] <- na_placeholder
        }

        return(replacement_values)
      }),
      .SDcols = allowed_na_columns
    ]
  }

  return(list(
    rules_for_validation = rules_for_validation,
    allowed_na_columns = allowed_na_columns
  ))
}

#' @title Ensure rule-referenced dataset columns exist
#' @description Adds any missing `column_source` or `column_target` columns
#' referenced by canonical rules to the dataset as `NA_character_` before
#' validation and rule execution.
#' @param dataset_dt Data table to mutate by reference.
#' @param rules_dt Canonical rule table.
#' @return Mutated `dataset_dt` with missing referenced columns initialized.
#' @importFrom checkmate assert_data_table assert_data_frame
#' @importFrom cli cli_abort
ensure_rule_referenced_columns <- function(dataset_dt, rules_dt) {
  checkmate::assert_data_table(dataset_dt)
  checkmate::assert_data_frame(rules_dt, min.rows = 0)

  existing_columns <- colnames(dataset_dt)

  if (anyDuplicated(existing_columns) > 0L) {
    duplicated_columns <- unique(existing_columns[duplicated(existing_columns)])

    cli::cli_abort(c(
      "dataset contains duplicate column names before rule-column materialization.",
      "x" = paste(duplicated_columns, collapse = ", ")
    ))
  }

  if (nrow(rules_dt) == 0L) {
    return(dataset_dt)
  }

  referenced_columns <- unique(c(
    rules_dt$column_source,
    rules_dt$column_target
  ))
  referenced_columns <- as.character(referenced_columns)
  referenced_columns <- trimws(referenced_columns)
  referenced_columns <- referenced_columns[
    !is.na(referenced_columns) & nzchar(referenced_columns)
  ]

  if (length(referenced_columns) == 0L) {
    return(dataset_dt)
  }

  missing_columns <- referenced_columns[
    !(referenced_columns %in% existing_columns)
  ]

  if (length(missing_columns) > 0L) {
    dataset_dt[, (missing_columns) := NA_character_]
  }

  return(dataset_dt)
}

#' @title Check type compatibility between rule values and dataset column
#' @description Validates that rule values can be safely cast to the type of
#' the corresponding dataset column (numeric, integer, or Date).
#' @param dataset_vector Atomic vector from the dataset column.
#' @param rule_values Atomic vector of rule values to check.
#' @param field_name Character scalar field label for error messages.
#' @param rule_file_id Character scalar rule file identifier for error context.
#' @param column_name Character scalar column name for error messages.
#' @return Invisibly returns `TRUE`.
#' @importFrom cli cli_abort
check_type_compatibility <- function(
  dataset_vector,
  rule_values,
  field_name,
  rule_file_id,
  column_name = "unknown"
) {
  non_missing_values <- rule_values[!is.na(rule_values)]

  if (is.factor(dataset_vector)) {
    non_missing_values <- as.character(non_missing_values)
  }

  if (is.numeric(dataset_vector)) {
    suppressWarnings(parsed_values <- as.numeric(non_missing_values))
    if (anyNA(parsed_values) && length(non_missing_values) > 0) {
      cli::cli_abort(c(
        "Type compatibility validation failed for {.file {rule_file_id}}.",
        "x" = paste0(
          field_name,
          " cannot be safely cast to numeric for column ",
          column_name
        )
      ))
    }
  }

  if (is.integer(dataset_vector)) {
    suppressWarnings(parsed_values <- as.integer(non_missing_values))
    if (anyNA(parsed_values) && length(non_missing_values) > 0) {
      cli::cli_abort(c(
        "Type compatibility validation failed for {.file {rule_file_id}}.",
        "x" = paste0(
          field_name,
          " cannot be safely cast to integer for column ",
          column_name
        )
      ))
    }
  }

  if (inherits(dataset_vector, "Date")) {
    suppressWarnings(parsed_values <- as.Date(non_missing_values))
    if (anyNA(parsed_values) && length(non_missing_values) > 0) {
      cli::cli_abort(c(
        "Type compatibility validation failed for {.file {rule_file_id}}.",
        "x" = paste0(
          field_name,
          " cannot be safely cast to Date for column ",
          column_name
        )
      ))
    }
  }

  return(invisible(TRUE))
}

#' @title Validate canonical rules
#' @description Validates schema completeness, dataset-column presence, rule-key
#' uniqueness, conflict-free mappings, and type compatibility.
#' @param rules_dt Canonical rule table.
#' @param dataset_dt Dataset to mutate.
#' @param rule_file_id Character scalar rule file identifier.
#' @param stage_name Character scalar execution stage label.
#' @return Invisibly returns `TRUE`.
#' @importFrom checkmate assert_data_frame assert_string
validate_canonical_rules <- function(
  rules_dt,
  dataset_dt,
  rule_file_id,
  stage_name
) {
  checkmate::assert_data_frame(rules_dt, min.rows = 0)
  checkmate::assert_data_frame(dataset_dt, min.rows = 0)
  checkmate::assert_string(rule_file_id, min.chars = 1)
  validated_stage_name <- validate_postpro_stage_name(stage_name)

  required_columns <- get_canonical_rule_columns()
  missing_rule_columns <- setdiff(required_columns, colnames(rules_dt))
  if (length(missing_rule_columns) > 0) {
    cli::cli_abort(c(
      "Canonical rule schema validation failed for {.file {rule_file_id}}.",
      "x" = paste(missing_rule_columns, collapse = ", ")
    ))
  }

  if (nrow(rules_dt) == 0) {
    return(invisible(TRUE))
  }

  validation_context <- normalize_rule_values_for_validation(
    rules_dt = rules_dt,
    stage_name = validated_stage_name
  )
  rules_for_validation <- validation_context$rules_for_validation
  allowed_na_columns <- validation_context$allowed_na_columns

  strict_required_columns <- setdiff(required_columns, allowed_na_columns)
  columns_with_na <- strict_required_columns[vapply(
    strict_required_columns,
    function(column_name) {
      anyNA(rules_dt[[column_name]])
    },
    logical(1)
  )]

  if (length(columns_with_na) > 0) {
    cli::cli_abort(c(
      "Rule file {.file {rule_file_id}} contains missing values in required columns.",
      "x" = paste(columns_with_na, collapse = ", ")
    ))
  }

  dataset_columns <- colnames(dataset_dt)
  source_columns <- unique(trimws(as.character(rules_dt$column_source)))
  target_columns <- unique(trimws(as.character(rules_dt$column_target)))
  source_columns <- source_columns[
    !is.na(source_columns) & nzchar(source_columns)
  ]
  target_columns <- target_columns[
    !is.na(target_columns) & nzchar(target_columns)
  ]

  missing_source <- setdiff(source_columns, dataset_columns)
  missing_target <- setdiff(target_columns, dataset_columns)

  if (length(missing_source) > 0 || length(missing_target) > 0) {
    cli::cli_abort(c(
      "Rule columns are not present in dataset for {.file {rule_file_id}}.",
      if (length(missing_source) > 0) {
        paste0("x source: ", paste(missing_source, collapse = ", "))
      },
      if (length(missing_target) > 0) {
        paste0("x target: ", paste(missing_target, collapse = ", "))
      }
    ))
  }

  duplicate_key_dt <- rules_for_validation[,
    .N,
    by = .(column_source, value_source_raw, column_target, value_target_raw)
  ][N > 1L]

  if (nrow(duplicate_key_dt) > 0) {
    cli::cli_abort(c(
      "Rule uniqueness validation failed for {.file {rule_file_id}}.",
      "x" = "Each (column_source, value_source_raw, column_target, value_target_raw) must be unique."
    ))
  }

  target_value_column <- get_stage_target_value_column(validated_stage_name)
  source_value_column <- get_stage_source_value_column(validated_stage_name)

  conflict_dt <- rules_for_validation[,
    .(target_value_count = data.table::uniqueN(get(target_value_column))),
    by = .(column_source, value_source_raw, column_target, value_target_raw)
  ][target_value_count > 1L]

  if (nrow(conflict_dt) > 0) {
    cli::cli_abort(c(
      "Conflicting rules detected in {.file {rule_file_id}}.",
      "x" = "A single source/target key maps to multiple target values."
    ))
  }

  source_conflict_dt <- rules_for_validation[,
    .(source_value_count = data.table::uniqueN(get(source_value_column))),
    by = .(column_source, value_source_raw, column_target, value_target_raw)
  ][source_value_count > 1L]

  if (nrow(source_conflict_dt) > 0) {
    cli::cli_abort(c(
      "Conflicting source rewrite rules detected in {.file {rule_file_id}}.",
      "x" = "A single (column_source, value_source_raw, column_target, value_target_raw) maps to multiple source result values."
    ))
  }

  rules_dt[,
    check_type_compatibility(
      dataset_dt[[column_source[1]]],
      value_source_raw,
      "value_source_raw",
      rule_file_id,
      column_name = column_source[1]
    ),
    by = column_source
  ]
  rules_dt[,
    check_type_compatibility(
      dataset_dt[[column_target[1]]],
      value_target_raw,
      "value_target_raw",
      rule_file_id,
      column_name = column_target[1]
    ),
    by = column_target
  ]

  rules_with_source_result <- rules_dt[!is.na(get(source_value_column))]
  if (nrow(rules_with_source_result) > 0L) {
    rules_with_source_result[,
      check_type_compatibility(
        dataset_dt[[column_source[1]]],
        get(source_value_column),
        source_value_column,
        rule_file_id,
        column_name = column_source[1]
      ),
      by = column_source
    ]
  }

  return(invisible(TRUE))
}

#' @title Build conditional dictionaries from canonical rules
#' @description Groups canonical rules by `(column_source, column_target)` and
#' sorts deterministically for reproducible execution.
#' @param rules_dt Canonical rules table.
#' @return List of grouped rule tables.
#' @importFrom checkmate assert_data_frame
build_conditional_rule_dictionary <- function(rules_dt, stage_name) {
  checkmate::assert_data_frame(rules_dt, min.rows = 0)
  validated_stage_name <- validate_postpro_stage_name(stage_name)

  if (nrow(rules_dt) == 0L) {
    return(list())
  }

  target_value_column <- get_stage_target_value_column(validated_stage_name)

  ordered_rules <- data.table::as.data.table(rules_dt)[order(
    column_source,
    column_target,
    value_source_raw,
    value_target_raw,
    get(target_value_column)
  )]

  grouped_rules <- split(
    x = ordered_rules,
    f = interaction(
      ordered_rules$column_source,
      ordered_rules$column_target,
      drop = TRUE
    ),
    drop = TRUE
  )

  return(grouped_rules)
}

#' @title Encode target rule values with internal missing placeholder
#' @description Converts empty strings and missing values in target rule values
#' to an explicit internal placeholder for deterministic downstream handling.
#' @param values Atomic vector values to encode.
#' @param na_placeholder Character scalar internal missing token.
#' @return Character vector with placeholder-encoded missing values.
#' @importFrom checkmate assert_atomic assert_string
