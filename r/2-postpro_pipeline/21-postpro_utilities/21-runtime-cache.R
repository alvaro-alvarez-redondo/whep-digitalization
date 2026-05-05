resolve_stage_runtime_cache_settings <- function(config) {
  checkmate::assert_list(config, min.len = 1)

  defaults <- get_pipeline_constants()$postpro$runtime_cache
  checkmate::assert_list(defaults, min.len = 1)

  configured_values <- defaults
  configured_postpro <- NULL
  if (is.list(config$postpro)) {
    configured_postpro <- config$postpro$runtime_cache
  }

  if (is.list(configured_postpro)) {
    configured_values <- utils::modifyList(defaults, configured_postpro)
  }

  enabled <- isTRUE(configured_values$enabled)
  cache_file_name <- as.character(configured_values$cache_file_name)
  suppressWarnings(max_entries <- as.integer(configured_values$max_entries))

  checkmate::assert_flag(enabled)
  checkmate::assert_string(cache_file_name, min.chars = 1)
  checkmate::assert_int(max_entries, lower = 1L)

  return(list(
    enabled = enabled,
    cache_file_name = cache_file_name,
    max_entries = max_entries
  ))
}

#' @title Build runtime cache file path for stage payload bundles
#' @description Returns deterministic cache file path under audit runtime-cache
#' directory.
#' @param config Named configuration list.
#' @param runtime_cache_settings Named runtime-cache settings.
#' @return Character scalar cache file path.
#' @importFrom checkmate assert_list assert_string
build_stage_runtime_cache_file_path <- function(
  config,
  runtime_cache_settings
) {
  checkmate::assert_list(config, min.len = 1)
  checkmate::assert_list(runtime_cache_settings, min.len = 1)
  checkmate::assert_string(
    config$paths$data$audit$runtime_cache_dir,
    min.chars = 1
  )
  checkmate::assert_string(
    runtime_cache_settings$cache_file_name,
    min.chars = 1
  )

  runtime_cache_dir <- config$paths$data$audit$runtime_cache_dir

  ensure_directories_exist(runtime_cache_dir, recurse = TRUE)

  return(fs::path(runtime_cache_dir, runtime_cache_settings$cache_file_name))
}

#' @title Prune cache entries deterministically
#' @description Applies deterministic pruning based on sorted cache-entry names.
#' @param cache_entries Named list of cache entries.
#' @param max_entries Integer scalar maximum entries to retain.
#' @return Pruned named list.
#' @importFrom checkmate assert_list assert_int
prune_runtime_cache_entries <- function(cache_entries, max_entries) {
  checkmate::assert_list(cache_entries)
  checkmate::assert_int(max_entries, lower = 1L)

  if (length(cache_entries) <= max_entries) {
    return(cache_entries)
  }

  entry_names <- names(cache_entries)
  if (is.null(entry_names)) {
    return(cache_entries[seq_len(max_entries)])
  }

  keep_names <- head(sort(entry_names), max_entries)

  return(cache_entries[keep_names])
}

#' @title Read runtime cache entries
#' @description Loads runtime cache entry list from disk with deterministic
#' pruning and defensive fallbacks.
#' @param cache_file_path Character scalar cache file path.
#' @param runtime_cache_settings Named runtime-cache settings.
#' @return Named list of cache entries.
#' @importFrom checkmate assert_string assert_list
read_stage_runtime_cache_entries <- function(
  cache_file_path,
  runtime_cache_settings
) {
  checkmate::assert_string(cache_file_path, min.chars = 1)
  checkmate::assert_list(runtime_cache_settings, min.len = 1)

  if (
    !isTRUE(runtime_cache_settings$enabled) || !file.exists(cache_file_path)
  ) {
    return(list())
  }

  loaded_entries <- tryCatch(
    readRDS(cache_file_path),
    error = function(error_condition) {
      cli::cli_warn(c(
        "failed to read runtime cache entries; rebuilding cache entry set.",
        "!" = error_condition$message
      ))

      list()
    }
  )

  if (!is.list(loaded_entries)) {
    return(list())
  }

  return(prune_runtime_cache_entries(
    cache_entries = loaded_entries,
    max_entries = as.integer(runtime_cache_settings$max_entries)
  ))
}

#' @title Persist runtime cache entries
#' @description Persists runtime cache entries to disk using deterministic
#' pruning and stable save semantics.
#' @param cache_entries Named list of cache entries.
#' @param cache_file_path Character scalar cache file path.
#' @param runtime_cache_settings Named runtime-cache settings.
#' @return Invisibly returns persisted cache file path.
#' @importFrom checkmate assert_list assert_string
persist_stage_runtime_cache_entries <- function(
  cache_entries,
  cache_file_path,
  runtime_cache_settings
) {
  checkmate::assert_list(cache_entries)
  checkmate::assert_string(cache_file_path, min.chars = 1)
  checkmate::assert_list(runtime_cache_settings, min.len = 1)

  if (!isTRUE(runtime_cache_settings$enabled)) {
    return(invisible(cache_file_path))
  }

  entries_to_persist <- prune_runtime_cache_entries(
    cache_entries = cache_entries,
    max_entries = as.integer(runtime_cache_settings$max_entries)
  )

  ensure_directories_exist(fs::path_dir(cache_file_path), recurse = TRUE)
  saveRDS(entries_to_persist, file = cache_file_path)

  return(invisible(cache_file_path))
}

#' @title Build deterministic stage payload cache key
#' @description Builds deterministic stage cache key from stage name and ordered
#' rule-file fingerprints.
#' @param config Named configuration list.
#' @param stage_name Character scalar stage label.
#' @return Character scalar cache key.
#' @importFrom checkmate assert_list assert_string
build_stage_payload_cache_key <- function(config, stage_name) {
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

  if (length(ordered_files) == 0L) {
    return(paste0(validated_stage_name, "::<no_rule_files>"))
  }

  file_checksums <- unname(tools::md5sum(ordered_files))
  file_fingerprints <- paste0(
    fs::path_file(ordered_files),
    "::",
    file_checksums
  )

  return(paste0(
    validated_stage_name,
    "::",
    paste(file_fingerprints, collapse = "||")
  ))
}

#' @title Load stage payload bundle from disk cache
#' @description Loads one stage payload bundle from runtime cache file by cache
#' key.
#' @param cache_file_path Character scalar cache file path.
#' @param runtime_cache_settings Named runtime-cache settings.
#' @param cache_key Character scalar stage payload cache key.
#' @return Stage payload bundle list or `NULL`.
#' @importFrom checkmate assert_string assert_list
load_stage_payload_bundle_from_disk <- function(
  cache_file_path,
  runtime_cache_settings,
  cache_key
) {
  checkmate::assert_string(cache_file_path, min.chars = 1)
  checkmate::assert_list(runtime_cache_settings, min.len = 1)
  checkmate::assert_string(cache_key, min.chars = 1)

  cache_entries <- read_stage_runtime_cache_entries(
    cache_file_path = cache_file_path,
    runtime_cache_settings = runtime_cache_settings
  )

  if (!(cache_key %in% names(cache_entries))) {
    return(NULL)
  }

  cached_bundle <- cache_entries[[cache_key]]

  if (!is.list(cached_bundle)) {
    return(NULL)
  }

  return(cached_bundle)
}

#' @title Persist stage payload bundle to disk cache
#' @description Persists one stage payload bundle under its cache key in runtime
#' cache file.
#' @param cache_file_path Character scalar cache file path.
#' @param runtime_cache_settings Named runtime-cache settings.
#' @param cache_key Character scalar stage payload cache key.
#' @param payload_bundle Named list payload bundle.
#' @return Invisibly returns persisted cache file path.
#' @importFrom checkmate assert_string assert_list
persist_stage_payload_bundle_to_disk <- function(
  cache_file_path,
  runtime_cache_settings,
  cache_key,
  payload_bundle
) {
  checkmate::assert_string(cache_file_path, min.chars = 1)
  checkmate::assert_list(runtime_cache_settings, min.len = 1)
  checkmate::assert_string(cache_key, min.chars = 1)
  checkmate::assert_list(payload_bundle, min.len = 1)

  if (!isTRUE(runtime_cache_settings$enabled)) {
    return(invisible(cache_file_path))
  }

  cache_entries <- read_stage_runtime_cache_entries(
    cache_file_path = cache_file_path,
    runtime_cache_settings = runtime_cache_settings
  )

  cache_entries[[cache_key]] <- payload_bundle

  return(persist_stage_runtime_cache_entries(
    cache_entries = cache_entries,
    cache_file_path = cache_file_path,
    runtime_cache_settings = runtime_cache_settings
  ))
}

#' @title Prune in-memory stage payload cache
#' @description Applies deterministic pruning to in-memory stage payload bundle
#' cache.
#' @param max_entries Integer scalar maximum in-memory entries.
#' @return Invisibly returns `TRUE`.
#' @importFrom checkmate assert_int
prune_stage_payload_bundle_memory_cache <- function(max_entries) {
  checkmate::assert_int(max_entries, lower = 1L)

  cache_names <- ls(envir = .stage_payload_bundle_cache, all.names = TRUE)
  if (length(cache_names) <= max_entries) {
    return(invisible(TRUE))
  }

  names_to_remove <- setdiff(
    sort(cache_names),
    head(sort(cache_names), max_entries)
  )

  if (length(names_to_remove) > 0L) {
    rm(list = names_to_remove, envir = .stage_payload_bundle_cache)
  }

  return(invisible(TRUE))
}

#' @title Get cached stage payload bundle
#' @description Returns canonical stage payload bundle using memory cache, then
#' disk cache, then rebuild-and-persist flow.
#' @param config Named configuration list.
#' @param stage_name Character scalar stage label.
#' @return Named list with `cache_key` and `canonical_payloads`.
#' @importFrom checkmate assert_list assert_string
get_cached_stage_payload_bundle <- function(config, stage_name) {
  checkmate::assert_list(config, min.len = 1)
  validated_stage_name <- validate_postpro_stage_name(stage_name)

  runtime_cache_settings <- resolve_stage_runtime_cache_settings(config)
  cache_key <- build_stage_payload_cache_key(
    config = config,
    stage_name = validated_stage_name
  )

  if (!isTRUE(runtime_cache_settings$enabled)) {
    payloads <- load_stage_rule_payloads(
      config = config,
      stage_name = validated_stage_name
    )

    canonical_payloads <- lapply(payloads, function(payload) {
      canonical_rules <- coerce_rule_schema(
        rule_dt = payload$raw_rules,
        stage_name = validated_stage_name,
        rule_file_id = payload$rule_file_id
      )

      list(
        rule_file_id = payload$rule_file_id,
        canonical_rules = canonical_rules
      )
    })

    return(list(
      cache_key = cache_key,
      canonical_payloads = canonical_payloads
    ))
  }

  if (
    exists(cache_key, envir = .stage_payload_bundle_cache, inherits = FALSE)
  ) {
    memory_bundle <- get(cache_key, envir = .stage_payload_bundle_cache)

    if (is.list(memory_bundle)) {
      return(memory_bundle)
    }
  }

  cache_file_path <- build_stage_runtime_cache_file_path(
    config = config,
    runtime_cache_settings = runtime_cache_settings
  )

  disk_bundle <- load_stage_payload_bundle_from_disk(
    cache_file_path = cache_file_path,
    runtime_cache_settings = runtime_cache_settings,
    cache_key = cache_key
  )

  if (is.list(disk_bundle)) {
    assign(cache_key, disk_bundle, envir = .stage_payload_bundle_cache)
    prune_stage_payload_bundle_memory_cache(
      max_entries = as.integer(runtime_cache_settings$max_entries)
    )

    return(disk_bundle)
  }

  payloads <- load_stage_rule_payloads(
    config = config,
    stage_name = validated_stage_name
  )

  canonical_payloads <- lapply(payloads, function(payload) {
    canonical_rules <- coerce_rule_schema(
      rule_dt = payload$raw_rules,
      stage_name = validated_stage_name,
      rule_file_id = payload$rule_file_id
    )

    list(
      rule_file_id = payload$rule_file_id,
      canonical_rules = canonical_rules
    )
  })

  payload_bundle <- list(
    cache_key = cache_key,
    canonical_payloads = canonical_payloads
  )

  assign(cache_key, payload_bundle, envir = .stage_payload_bundle_cache)
  prune_stage_payload_bundle_memory_cache(
    max_entries = as.integer(runtime_cache_settings$max_entries)
  )

  persist_stage_payload_bundle_to_disk(
    cache_file_path = cache_file_path,
    runtime_cache_settings = runtime_cache_settings,
    cache_key = cache_key,
    payload_bundle = payload_bundle
  )

  return(payload_bundle)
}

#' @title Build layer diagnostics from audit table
#' @description Generates deterministic diagnostics summary for one stage.
#' @param layer_name Character scalar stage label.
#' @param rows_in Integer scalar rows before stage.
#' @param rows_out Integer scalar rows after stage.
#' @param audit_dt Audit table generated by harmonization engine.
#' @return Named diagnostics list.
#' @importFrom checkmate assert_string assert_int assert_data_frame
