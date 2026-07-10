# script: checkpointing
# description: helpers for saving and restoring pipeline checkpoints. every
# checkpoint carries a fingerprint of its input state (input-dir file listing,
# config, producing code) so stale checkpoints are rebuilt instead of served.

#' @title Resolve checkpoint directory
#' @description Returns the checkpoint directory under the project data root.
#' Uses `config$project_root` when present so tests and alternate roots keep
#' checkpoints isolated; falls back to `here::here()`.
#' @param config Named configuration list.
#' @return `fs_path` scalar checkpoint directory.
#' @importFrom checkmate test_string
#' @importFrom fs path
#' @importFrom here here
resolve_checkpoint_dir <- function(config) {
  constants <- get_pipeline_constants()

  checkpoint_root <- config$project_root
  if (!checkmate::test_string(checkpoint_root, min.chars = 1)) {
    checkpoint_root <- here::here()
  }

  return(fs::path(
    checkpoint_root,
    constants$paths$data_dir,
    constants$paths$checkpoints_dir
  ))
}


#' @title Build input-directory listing for checkpoint fingerprints
#' @description Lists files under one input directory (recursive, restricted to
#' `input_file_glob`) as parallel vectors of relative path, size, and mtime.
#' Unresolvable or missing directories yield a sentinel entry so the resulting
#' fingerprint never matches a listing of real files.
#' @param input_dir Character scalar input directory, or `NULL` when the config
#' key did not resolve.
#' @param input_file_glob Character scalar glob restricting listed files.
#' @return Named list with either `dir` + `missing`, or `dir` + `path` + `size`
#' + `mtime`.
#' @importFrom checkmate test_string
#' @importFrom fs dir_exists dir_info path_rel
build_checkpoint_input_listing <- function(input_dir, input_file_glob) {
  if (!checkmate::test_string(input_dir, min.chars = 1)) {
    return(list(dir = NA_character_, missing = TRUE))
  }

  if (!fs::dir_exists(input_dir)) {
    return(list(dir = as.character(input_dir), missing = TRUE))
  }

  file_info <- fs::dir_info(
    path = input_dir,
    recurse = TRUE,
    type = "file",
    glob = input_file_glob
  )

  relative_paths <- as.character(
    fs::path_rel(file_info$path, start = input_dir)
  )
  # radix = C-locale ordering, deterministic across sessions and locales
  listing_order <- order(relative_paths, method = "radix")

  return(list(
    dir = as.character(input_dir),
    path = relative_paths[listing_order],
    size = as.numeric(file_info$size)[listing_order],
    mtime = as.numeric(file_info$modification_time)[listing_order]
  ))
}


#' @title Build code fingerprint for checkpoint invalidation
#' @description Returns md5 fingerprints (`relative_path::md5`) of every `.R`
#' file under the given project-relative directories, mirroring the
#' content-addressed pattern of `build_stage_payload_cache_key()`.
#' @param code_dirs Character vector of project-relative directories, or `NULL`.
#' @return Character vector of fingerprints (empty when `code_dirs` is empty).
#' @importFrom fs path dir_exists dir_ls path_rel
#' @importFrom here here
build_checkpoint_code_fingerprint <- function(code_dirs) {
  if (length(code_dirs) == 0) {
    return(character(0))
  }

  project_root <- here::here()

  fingerprints <- lapply(code_dirs, function(code_dir) {
    code_dir_path <- fs::path(project_root, code_dir)

    if (!fs::dir_exists(code_dir_path)) {
      return(paste0(code_dir, "::<missing_dir>"))
    }

    code_files <- fs::dir_ls(
      path = code_dir_path,
      recurse = TRUE,
      type = "file",
      regexp = "\\.[Rr]$"
    )

    relative_paths <- as.character(
      fs::path_rel(code_files, start = project_root)
    )
    file_order <- order(relative_paths, method = "radix")
    checksums <- unname(tools::md5sum(as.character(code_files)))

    return(paste0(
      relative_paths[file_order],
      "::",
      checksums[file_order]
    ))
  })

  return(unlist(fingerprints, use.names = FALSE))
}


#' @title Build checkpoint fingerprint
#' @description Builds the input-state fingerprint stored inside checkpoint
#' payloads and recomputed on load: input-directory listings and code md5s from
#' the `constants$checkpoints$fingerprint_sources` registry entry for
#' `checkpoint_name`, plus the config minus excluded fields (performance knobs
#' do not change output). Unregistered checkpoint names are fingerprinted on
#' config alone.
#' @param checkpoint_name Character scalar checkpoint identifier.
#' @param config Named configuration list.
#' @return Named list with `inputs`, `config`, and `code`.
#' @importFrom checkmate check_string check_list
build_checkpoint_fingerprint <- function(checkpoint_name, config) {
  assert_or_abort(checkmate::check_string(checkpoint_name, min.chars = 1))
  assert_or_abort(checkmate::check_list(config, min.len = 1))

  checkpoint_constants <- get_pipeline_constants()$checkpoints
  fingerprint_sources <-
    checkpoint_constants$fingerprint_sources[[checkpoint_name]]

  input_listings <- list()
  if (!is.null(fingerprint_sources)) {
    input_listings <- lapply(
      fingerprint_sources$input_dir_keys,
      function(dir_key) {
        input_dir <- config
        for (key_part in dir_key) {
          input_dir <- input_dir[[key_part]]
          if (is.null(input_dir)) {
            break
          }
        }

        listing <- build_checkpoint_input_listing(
          input_dir = input_dir,
          input_file_glob = fingerprint_sources$input_file_glob
        )
        listing$key <- paste(dir_key, collapse = "$")

        return(listing)
      }
    )
  }

  config_fields <- sort(setdiff(
    names(config),
    checkpoint_constants$config_exclude_fields
  ))

  return(list(
    inputs = input_listings,
    config = config[config_fields],
    code = build_checkpoint_code_fingerprint(fingerprint_sources$code_dirs)
  ))
}


#' @title Save pipeline checkpoint to disk
#' @description Serializes a pipeline result to an RDS file for crash recovery
#' and resumption of long-running pipeline stages. The payload carries the
#' checkpoint fingerprint (see `build_checkpoint_fingerprint()`), computed at
#' save time, which `load_pipeline_checkpoint()` re-validates. When
#' checkpointing is disabled via options, this function silently returns
#' `NULL`.
#' @param result Object to serialize.
#' @param checkpoint_name Character scalar checkpoint identifier.
#' @param config Named configuration list; `project_root` overrides the
#' checkpoint storage root (default `here::here()`).
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

  checkpoint_dir <- resolve_checkpoint_dir(config)
  fs::dir_create(checkpoint_dir, recurse = TRUE)

  checkpoint_path <- fs::path(checkpoint_dir, paste0(checkpoint_name, ".rds"))
  checkpoint_payload <- list(
    format = constants$checkpoints$payload_format,
    fingerprint = build_checkpoint_fingerprint(checkpoint_name, config),
    result = result
  )
  # compress = FALSE prioritizes speed over disk space, appropriate for
  # checkpoint files that are temporary and frequently overwritten.
  saveRDS(checkpoint_payload, file = checkpoint_path, compress = FALSE)

  cli::cli_alert_info("Checkpoint saved: {.file {checkpoint_path}}")

  return(checkpoint_path)
}


#' @title Load pipeline checkpoint from disk
#' @description Attempts to load a previously saved checkpoint. Returns `NULL`
#' when no checkpoint file exists, checkpointing is disabled, the payload is
#' unreadable or predates the current payload format, or the stored fingerprint
#' no longer matches the current input state (input files, config, or pipeline
#' code changed) — each rejection logs its reason so the stage rebuilds from
#' source instead of serving stale results.
#' @param checkpoint_name Character scalar checkpoint identifier.
#' @param config Named configuration list; `project_root` overrides the
#' checkpoint storage root (default `here::here()`).
#' @return Deserialized checkpoint result, or `NULL`.
#' @importFrom checkmate check_string check_list
#' @importFrom fs path file_exists
#' @importFrom cli cli_alert_success cli_alert_info cli_warn
load_pipeline_checkpoint <- function(checkpoint_name, config) {
  assert_or_abort(checkmate::check_string(checkpoint_name, min.chars = 1))
  assert_or_abort(checkmate::check_list(config, min.len = 1))

  constants <- get_pipeline_constants()
  checkpoint_option <- constants$options$checkpointing_enabled

  if (!isTRUE(getOption(checkpoint_option, FALSE))) {
    return(NULL)
  }

  checkpoint_path <- fs::path(
    resolve_checkpoint_dir(config),
    paste0(checkpoint_name, ".rds")
  )

  if (!fs::file_exists(checkpoint_path)) {
    return(NULL)
  }

  checkpoint_payload <- tryCatch(
    readRDS(checkpoint_path),
    error = function(read_error) {
      cli::cli_warn(c(
        "failed to read checkpoint {.file {checkpoint_path}}; rebuilding stage.",
        "!" = conditionMessage(read_error)
      ))

      NULL
    }
  )

  if (is.null(checkpoint_payload)) {
    return(NULL)
  }

  has_current_format <- is.list(checkpoint_payload) &&
    identical(
      checkpoint_payload$format,
      constants$checkpoints$payload_format
    ) &&
    all(c("fingerprint", "result") %in% names(checkpoint_payload))

  if (!has_current_format) {
    cli::cli_alert_info(
      "Checkpoint ignored (payload format mismatch): {.file {checkpoint_path}}; rebuilding stage."
    )
    return(NULL)
  }

  expected_fingerprint <- build_checkpoint_fingerprint(checkpoint_name, config)

  if (!identical(checkpoint_payload$fingerprint, expected_fingerprint)) {
    fingerprint_components <- union(
      names(expected_fingerprint),
      names(checkpoint_payload$fingerprint)
    )
    stale_components <- fingerprint_components[
      vapply(
        fingerprint_components,
        function(component) {
          !identical(
            checkpoint_payload$fingerprint[[component]],
            expected_fingerprint[[component]]
          )
        },
        logical(1)
      )
    ]
    if (length(stale_components) == 0) {
      stale_components <- "fingerprint"
    }

    cli::cli_alert_info(
      "Checkpoint stale ({stale_components} changed): {.file {checkpoint_path}}; rebuilding stage."
    )
    return(NULL)
  }

  cli::cli_alert_success("Checkpoint restored: {.file {checkpoint_path}}")

  return(checkpoint_payload$result)
}


#' @title Clear pipeline checkpoints
#' @description Removes checkpoint directory and all saved checkpoints.
#' @param config Named configuration list; `project_root` overrides the
#' checkpoint storage root (default `here::here()`).
#' @return Invisible `TRUE`.
#' @importFrom checkmate check_list
#' @importFrom fs dir_exists dir_delete
#' @importFrom cli cli_alert_info
clear_pipeline_checkpoints <- function(config) {
  assert_or_abort(checkmate::check_list(config, min.len = 1))

  checkpoint_dir <- resolve_checkpoint_dir(config)

  if (fs::dir_exists(checkpoint_dir)) {
    fs::dir_delete(checkpoint_dir)
    cli::cli_alert_info("Checkpoints cleared: {.file {checkpoint_dir}}")
  }

  return(invisible(TRUE))
}
