# script: post-processing utilities
# description: reusable stage metadata, template generation, rule validation,
# dictionary construction, vectorized harmonization engine, and structured
# audit helpers for post-processing stages.

#' @title Get canonical rule columns
#' @description Returns unified canonical rule column names used by both
#' `clean` and `harmonize` post-processing stages.
#' @return Character vector of canonical columns.
#' @examples
#' get_canonical_rule_columns()
get_canonical_rule_columns <- function() {
  return(c(
    "column_source",
    "value_source_raw",
    "value_source",
    "column_target",
    "value_target_raw",
    "value_target"
  ))
}

#' @title Get supported post-processing stages
#' @description Returns deterministic stage order for post-processing execution.
#' @return Character vector with values `clean` and `harmonize`.
#' @examples
#' get_postpro_stage_names()
get_postpro_stage_names <- function() {
  return(c("clean", "harmonize"))
}

# Shared in-memory cache for canonical stage payload bundles.
.stage_payload_bundle_cache <- new.env(parent = emptyenv())

#' @title Validate post-processing stage name
#' @description Ensures stage name is one of the supported post-processing stages.
#' @param stage_name Character scalar stage label.
#' @return Character scalar validated stage name.
#' @importFrom checkmate assert_string
validate_postpro_stage_name <- function(stage_name) {
  checkmate::assert_string(stage_name, min.chars = 1)
  validated_stage_name <- match.arg(
    stage_name,
    choices = get_postpro_stage_names()
  )

  return(validated_stage_name)
}

#' @title Get canonical target value column for stage
#' @description Returns unified target value column name used by both stages.
#' @param stage_name Character scalar stage label.
#' @return Character scalar target value column name.
get_stage_target_value_column <- function(stage_name) {
  validate_postpro_stage_name(stage_name)

  return("value_target")
}

#' @title Get canonical source value column for stage
#' @description Returns unified source value column name used by both stages.
#' @param stage_name Character scalar stage label.
#' @return Character scalar source value column name.
get_stage_source_value_column <- function(stage_name) {
  validate_postpro_stage_name(stage_name)

  return("value_source")
}

#' @title Get post-processing output paths
#' @description Resolves deterministic post-processing root and leaf directories.
#' @param config Named configuration list.
#' @return Named list with `audit_root_dir`, `audit_dir`, `diagnostics_dir`,
#'   `templates_dir`, and `runtime_cache_dir`.
#' @importFrom checkmate assert_list assert_string
