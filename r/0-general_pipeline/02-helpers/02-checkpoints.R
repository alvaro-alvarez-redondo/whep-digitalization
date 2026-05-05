# script: checkpointing
# description: helpers for saving and restoring pipeline checkpoints.

#' @title Save pipeline checkpoint to disk
#' @description Serializes a pipeline result to an RDS file for crash recovery
#' and resumption of long-running pipeline stages. When checkpointing is
#' disabled via options, this function silently returns `NULL`.
#' @param result Object to serialize.
#' @param checkpoint_name Character scalar checkpoint identifier.
#' @param config Named configuration list with `paths$data` containing the
#' project data root.
#' @return Character scalar path to the checkpoint file, or `NULL` when
#' checkpointing is disabled.
#' @importFrom checkmate check_string check_list
#' @importFrom fs path dir_create
#' @importFrom cli cli_alert_info
save_pipeline_checkpoint <- function(result, checkpoint_name, config) {
  assert_or_abort(checkmate::check_string(checkpoint_name, min.chars = 1))
  assert_or_abort(checkmate::check_list(config, min.len = 1))

  constants <- get_pipeline_constants()
  checkpoint_option <- constants$options$checkpointing_enabled

  if (!isTRUE(getOption(checkpoint_option, FALSE))) {
    return(invisible(NULL))
  }

  checkpoint_dir <- fs::path(
    here::here(),
    constants$paths$data_dir,
    constants$paths$checkpoints_dir
  )
  fs::dir_create(checkpoint_dir, recurse = TRUE)

  checkpoint_path <- fs::path(checkpoint_dir, paste0(checkpoint_name, ".rds"))
  # compress = FALSE prioritizes speed over disk space, appropriate for
  # checkpoint files that are temporary and frequently overwritten.
  saveRDS(result, file = checkpoint_path, compress = FALSE)

  cli::cli_alert_info("Checkpoint saved: {.file {checkpoint_path}}")

  return(checkpoint_path)
}


#' @title Load pipeline checkpoint from disk
#' @description Attempts to load a previously saved checkpoint. Returns `NULL`
#' when no checkpoint file exists or checkpointing is disabled.
#' @param checkpoint_name Character scalar checkpoint identifier.
#' @param config Named configuration list.
#' @return Deserialized checkpoint object, or `NULL`.
#' @importFrom checkmate check_string check_list
#' @importFrom fs path file_exists
#' @importFrom cli cli_alert_success
load_pipeline_checkpoint <- function(checkpoint_name, config) {
  assert_or_abort(checkmate::check_string(checkpoint_name, min.chars = 1))
  assert_or_abort(checkmate::check_list(config, min.len = 1))

  constants <- get_pipeline_constants()
  checkpoint_option <- constants$options$checkpointing_enabled

  if (!isTRUE(getOption(checkpoint_option, FALSE))) {
    return(NULL)
  }

  checkpoint_path <- fs::path(
    here::here(),
    constants$paths$data_dir,
    constants$paths$checkpoints_dir,
    paste0(checkpoint_name, ".rds")
  )

  if (!fs::file_exists(checkpoint_path)) {
    return(NULL)
  }

  result <- readRDS(checkpoint_path)
  cli::cli_alert_success("Checkpoint restored: {.file {checkpoint_path}}")

  return(result)
}


#' @title Clear pipeline checkpoints
#' @description Removes checkpoint directory and all saved checkpoints.
#' @param config Named configuration list.
#' @return Invisible `TRUE`.
#' @importFrom checkmate check_list
#' @importFrom fs path dir_exists dir_delete
#' @importFrom cli cli_alert_info
clear_pipeline_checkpoints <- function(config) {
  assert_or_abort(checkmate::check_list(config, min.len = 1))

  constants <- get_pipeline_constants()
  checkpoint_dir <- fs::path(
    here::here(),
    constants$paths$data_dir,
    constants$paths$checkpoints_dir
  )

  if (fs::dir_exists(checkpoint_dir)) {
    fs::dir_delete(checkpoint_dir)
    cli::cli_alert_info("Checkpoints cleared: {.file {checkpoint_dir}}")
  }

  return(invisible(TRUE))
}
