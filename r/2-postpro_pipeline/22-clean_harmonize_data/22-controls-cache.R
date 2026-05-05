resolve_stage_multi_pass_controls <- function(config, stage_name) {
  checkmate::assert_list(config, min.len = 1)
  validated_stage_name <- validate_postpro_stage_name(stage_name)

  defaults <- get_pipeline_constants()$postpro$multi_pass
  checkmate::assert_list(defaults, min.len = 1)

  default_enabled_by_stage <- defaults$enabled_by_stage
  if (is.list(default_enabled_by_stage)) {
    default_enabled_by_stage <- unlist(
      default_enabled_by_stage,
      recursive = FALSE,
      use.names = TRUE
    )
  }
  checkmate::assert_logical(default_enabled_by_stage, any.missing = FALSE)

  default_max_passes_by_stage <- defaults$max_passes_by_stage
  if (is.list(default_max_passes_by_stage)) {
    default_max_passes_by_stage <- unlist(
      default_max_passes_by_stage,
      recursive = FALSE,
      use.names = TRUE
    )
  }
  if (!is.integer(default_max_passes_by_stage)) {
    suppressWarnings(
      default_max_passes_by_stage <- as.integer(
        default_max_passes_by_stage
      )
    )
  }
  checkmate::assert_integer(
    default_max_passes_by_stage,
    lower = 1L,
    any.missing = FALSE
  )

  configured_values <- defaults
  configured_multi_pass <- NULL
  if (is.list(config$postpro)) {
    configured_multi_pass <- config$postpro$multi_pass
  }
  if (is.list(configured_multi_pass)) {
    configured_values <- utils::modifyList(defaults, configured_multi_pass)
  }

  enabled_by_stage <- configured_values$enabled_by_stage
  if (is.list(enabled_by_stage)) {
    enabled_by_stage <- unlist(
      enabled_by_stage,
      recursive = FALSE,
      use.names = TRUE
    )
  }
  checkmate::assert_logical(enabled_by_stage, any.missing = FALSE)

  if (
    is.null(names(enabled_by_stage)) ||
      any(!nzchar(trimws(names(enabled_by_stage))))
  ) {
    cli::cli_abort("multi-pass enabled_by_stage must be a named logical vector")
  }

  if (!(validated_stage_name %in% names(enabled_by_stage))) {
    missing_enable_stages <- setdiff(
      names(default_enabled_by_stage),
      names(enabled_by_stage)
    )

    if (length(missing_enable_stages) > 0L) {
      enabled_by_stage <- c(
        enabled_by_stage,
        default_enabled_by_stage[missing_enable_stages]
      )
    }
  }

  enabled_by_stage <- enabled_by_stage[names(default_enabled_by_stage)]

  if (!(validated_stage_name %in% names(enabled_by_stage))) {
    cli::cli_abort(c(
      "multi-pass configuration is missing a stage enable flag.",
      "x" = paste0("stage: ", validated_stage_name)
    ))
  }

  max_passes_by_stage <- configured_values$max_passes_by_stage
  if (is.list(max_passes_by_stage)) {
    max_passes_by_stage <- unlist(
      max_passes_by_stage,
      recursive = FALSE,
      use.names = TRUE
    )
  }

  if (!is.integer(max_passes_by_stage)) {
    suppressWarnings(max_passes_by_stage <- as.integer(max_passes_by_stage))
  }
  checkmate::assert_integer(
    max_passes_by_stage,
    lower = 1L,
    any.missing = FALSE
  )

  if (
    is.null(names(max_passes_by_stage)) ||
      any(!nzchar(trimws(names(max_passes_by_stage))))
  ) {
    cli::cli_abort(
      "multi-pass max_passes_by_stage must be a named integer vector"
    )
  }

  if (!(validated_stage_name %in% names(max_passes_by_stage))) {
    missing_max_passes_stages <- setdiff(
      names(default_max_passes_by_stage),
      names(max_passes_by_stage)
    )

    if (length(missing_max_passes_stages) > 0L) {
      max_passes_by_stage <- c(
        max_passes_by_stage,
        default_max_passes_by_stage[missing_max_passes_stages]
      )
    }
  }

  max_passes_by_stage <- max_passes_by_stage[names(default_max_passes_by_stage)]

  if (!(validated_stage_name %in% names(max_passes_by_stage))) {
    cli::cli_abort(c(
      "multi-pass configuration is missing a stage max-pass value.",
      "x" = paste0("stage: ", validated_stage_name)
    ))
  }

  supported_cycle_policies <- configured_values$supported_cycle_policies
  checkmate::assert_character(
    supported_cycle_policies,
    min.len = 1,
    any.missing = FALSE,
    unique = TRUE
  )

  supported_diagnostics_verbosity <- configured_values$supported_diagnostics_verbosity
  checkmate::assert_character(
    supported_diagnostics_verbosity,
    min.len = 1,
    any.missing = FALSE,
    unique = TRUE
  )

  cycle_policy <- as.character(configured_values$cycle_policy)
  diagnostics_verbosity <- as.character(configured_values$diagnostics_verbosity)

  if (!(cycle_policy %in% supported_cycle_policies)) {
    cli::cli_abort(c(
      "invalid multi-pass cycle policy.",
      "x" = paste0("configured value: ", cycle_policy),
      "x" = paste0(
        "supported values: ",
        paste(supported_cycle_policies, collapse = ", ")
      )
    ))
  }

  if (!(diagnostics_verbosity %in% supported_diagnostics_verbosity)) {
    cli::cli_abort(c(
      "invalid multi-pass diagnostics verbosity.",
      "x" = paste0("configured value: ", diagnostics_verbosity),
      "x" = paste0(
        "supported values: ",
        paste(supported_diagnostics_verbosity, collapse = ", ")
      )
    ))
  }

  return(list(
    enabled = isTRUE(enabled_by_stage[[validated_stage_name]]),
    max_passes = as.integer(max_passes_by_stage[[validated_stage_name]]),
    cycle_policy = cycle_policy,
    diagnostics_verbosity = diagnostics_verbosity
  ))
}

#' @title Resolve schema-validation cache settings
#' @description Resolves schema-validation memoization settings from centralized
#' defaults with optional configuration overrides.
#' @param config Named configuration list.
#' @return Named list with `enabled` and `max_entries`.
#' @importFrom checkmate assert_list assert_flag assert_int
resolve_schema_validation_cache_settings <- function(config) {
  checkmate::assert_list(config, min.len = 1)

  defaults <- get_pipeline_constants()$postpro$schema_validation_cache
  checkmate::assert_list(defaults, min.len = 1)

  configured_values <- defaults
  configured_postpro <- NULL
  if (is.list(config$postpro)) {
    configured_postpro <- config$postpro$schema_validation_cache
  }

  if (is.list(configured_postpro)) {
    configured_values <- utils::modifyList(defaults, configured_postpro)
  }

  enabled <- isTRUE(configured_values$enabled)
  suppressWarnings(max_entries <- as.integer(configured_values$max_entries))

  checkmate::assert_flag(enabled)
  checkmate::assert_int(max_entries, lower = 1L)

  return(list(
    enabled = enabled,
    max_entries = max_entries
  ))
}

#' @title Build schema-validation dependency signature
#' @description Builds deterministic dependency signature for schema validation
#' memoization.
#' @param dataset_dt Data table to validate against.
#' @param canonical_rules Canonical rule table.
#' @param stage_name Character scalar stage label.
#' @param rule_file_id Character scalar rule-file identifier.
#' @param payload_cache_key Character scalar stage payload cache key.
#' @return Character scalar dependency signature.
#' @importFrom checkmate assert_data_table assert_data_frame assert_string
build_schema_validation_dependency_signature <- function(
  dataset_dt,
  canonical_rules,
  stage_name,
  rule_file_id,
  payload_cache_key
) {
  checkmate::assert_data_table(dataset_dt)
  checkmate::assert_data_frame(canonical_rules, min.rows = 0)
  validated_stage_name <- validate_postpro_stage_name(stage_name)
  checkmate::assert_string(rule_file_id, min.chars = 1)
  checkmate::assert_string(payload_cache_key, min.chars = 1)

  referenced_columns <- unique(c(
    canonical_rules$column_source,
    canonical_rules$column_target
  ))
  referenced_columns <- as.character(referenced_columns)
  referenced_columns <- trimws(referenced_columns)
  referenced_columns <- referenced_columns[
    !is.na(referenced_columns) & nzchar(referenced_columns)
  ]
  referenced_columns <- sort(unique(referenced_columns))

  referenced_column_classes <- vapply(
    referenced_columns,
    function(column_name) {
      if (!(column_name %in% names(dataset_dt))) {
        return("<missing>")
      }

      paste(class(dataset_dt[[column_name]]), collapse = "|")
    },
    character(1)
  )

  signature_payload <- list(
    stage_name = validated_stage_name,
    rule_file_id = rule_file_id,
    payload_cache_key = payload_cache_key,
    referenced_columns = referenced_columns,
    referenced_column_classes = referenced_column_classes
  )

  signature_raw <- serialize(
    signature_payload,
    connection = NULL,
    ascii = FALSE,
    version = 2
  )

  return(paste(as.integer(signature_raw), collapse = "-"))
}

#' @title Query schema-validation signature cache
#' @description Returns whether dependency signature is already memoized.
#' @param dependency_signature Character scalar dependency signature.
#' @param cache_settings Named schema-validation cache settings.
#' @return Logical scalar cache-hit flag.
#' @importFrom checkmate assert_string assert_list
is_schema_validation_signature_cached <- function(
  dependency_signature,
  cache_settings
) {
  checkmate::assert_string(dependency_signature, min.chars = 1)
  checkmate::assert_list(cache_settings, min.len = 1)

  if (!isTRUE(cache_settings$enabled)) {
    return(FALSE)
  }

  return(exists(
    dependency_signature,
    envir = .schema_validation_signature_cache,
    inherits = FALSE
  ))
}

#' @title Memoize schema-validation dependency signature
#' @description Stores dependency signature in memoization cache with
#' deterministic pruning.
#' @param dependency_signature Character scalar dependency signature.
#' @param cache_settings Named schema-validation cache settings.
#' @return Invisibly returns `TRUE`.
#' @importFrom checkmate assert_string assert_list
memoize_schema_validation_signature <- function(
  dependency_signature,
  cache_settings
) {
  checkmate::assert_string(dependency_signature, min.chars = 1)
  checkmate::assert_list(cache_settings, min.len = 1)

  if (!isTRUE(cache_settings$enabled)) {
    return(invisible(TRUE))
  }

  assign(
    dependency_signature,
    TRUE,
    envir = .schema_validation_signature_cache
  )

  cache_names <- ls(
    envir = .schema_validation_signature_cache,
    all.names = TRUE
  )
  max_entries <- as.integer(cache_settings$max_entries)

  if (length(cache_names) > max_entries) {
    names_to_remove <- setdiff(
      sort(cache_names),
      head(sort(cache_names), max_entries)
    )

    if (length(names_to_remove) > 0L) {
      rm(list = names_to_remove, envir = .schema_validation_signature_cache)
    }
  }

  return(invisible(TRUE))
}

#' @title Serialize stage state signature
#' @description Generates a deterministic raw signature for a stage state.
#' @param dataset_dt Stage dataset as data.table.
#' @return Raw vector state signature.
#' @importFrom checkmate assert_data_table
serialize_stage_state_signature <- function(dataset_dt) {
  checkmate::assert_data_table(dataset_dt)

  return(serialize(dataset_dt, connection = NULL, ascii = FALSE, version = 2))
}

#' @title Find repeated stage-state signature
#' @description Returns prior pass index when a state signature already exists.
#' @param state_signatures List of prior raw state signatures.
#' @param state_pass_indexes Integer vector pass indexes aligned to signatures.
#' @param candidate_signature Raw vector candidate signature.
#' @return Integer scalar repeated pass index or `NA_integer_`.
#' @importFrom checkmate assert_list assert_integer assert_raw
find_repeated_stage_state_pass <- function(
  state_signatures,
  state_pass_indexes,
  candidate_signature
) {
  checkmate::assert_list(state_signatures)
  checkmate::assert_integer(state_pass_indexes, any.missing = FALSE)
  checkmate::assert_raw(candidate_signature, min.len = 1)

  if (length(state_signatures) != length(state_pass_indexes)) {
    cli::cli_abort(
      "state-signature and pass-index vectors must have equal length"
    )
  }

  if (length(state_signatures) == 0L) {
    return(NA_integer_)
  }

  matches <- which(vapply(
    state_signatures,
    function(existing_signature) {
      identical(existing_signature, candidate_signature)
    },
    logical(1)
  ))

  if (length(matches) == 0L) {
    return(NA_integer_)
  }

  return(as.integer(state_pass_indexes[[matches[[1]]]]))
}

#' @title Run one rule-based post-processing stage
#' @description Applies one stage of rule payloads (`clean` or `harmonize`) and
#' returns transformed data with deterministic diagnostics and audit metadata.
#' @param dataset_dt Input dataset as data.frame/data.table.
#' @param config Named configuration list.
#' @param stage_name Character scalar stage name (`clean` or `harmonize`).
#' @param dataset_name Character scalar dataset identifier.
#' @return `data.table` with attributes `layer_diagnostics` and `layer_audit`.
#' @importFrom checkmate assert_data_frame assert_list assert_string
#' @importFrom data.table as.data.table copy rbindlist
#' @importFrom purrr reduce
