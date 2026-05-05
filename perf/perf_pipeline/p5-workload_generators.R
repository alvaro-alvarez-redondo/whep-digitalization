#' @title Workload generator module
#' @description Benchmark descriptor builders organized by pipeline stage.
#'   Each descriptor contains metadata and a function factory for one benchmark.
#' @keywords internal
#' @noRd
NULL

# ── 5. workload generators ────────────────────────────────────────────────────
#
# each benchmark descriptor is a named list with:
#   name        : unique identifier (used for reporting and plot file names)
#   stage       : pipeline stage label (one of "0-general", "1-import",
#                 "2-postpro", "3-export")
#   description : one-line summary of what is measured
#   fn_factory  : function(n) → function() that runs the target operation once
#
# fn_factory must be self-contained (capture everything via closure).

#' @title Resolve integer benchmark config field
#' @description Return an integer scalar from optional config values, with a
#'   deterministic fallback.
#' @param x Candidate scalar value.
#' @param fallback Integer scalar fallback.
#' @return Integer scalar.
#' @keywords internal
#' @noRd
.resolve_integer_cfg <- function(x, fallback) {
  x_int <- suppressWarnings(as.integer(x))
  if (length(x_int) != 1L || is.na(x_int)) {
    return(as.integer(fallback))
  }
  return(as.integer(x_int))
}

#' @title Scale Excel discovery workload
#' @description Map benchmark input size to a bounded number of workbook files
#'   used for file discovery timing.
#' @param n Integer scalar benchmark input size.
#' @param max_workbooks Integer scalar upper bound.
#' @param scale_divisor Integer scalar that maps benchmark n to workbook count
#'   by ceiling(n / scale_divisor).
#' @return Integer scalar workbook count.
#' @keywords internal
#' @noRd
.scale_excel_discovery_workbook_count <- function(
  n,
  max_workbooks,
  scale_divisor = 1000L
) {
  safe_n <- max(1L, suppressWarnings(as.integer(n)))
  safe_max <- max(1L, suppressWarnings(as.integer(max_workbooks)))
  safe_divisor <- max(1L, suppressWarnings(as.integer(scale_divisor)))
  workbook_count <- as.integer(ceiling(safe_n / safe_divisor))
  return(max(1L, min(safe_max, workbook_count)))
}

#' @title Scale Excel sheet-read workload
#' @description Map benchmark input size to number of worksheet reads per timed
#'   invocation while bounding runtime.
#' @param n Integer scalar benchmark input size interpreted as sheet reads.
#' @param max_sheet_reads Integer scalar upper bound for sheet reads per
#'   invocation.
#' @return Integer scalar sheet reads per invocation.
#' @keywords internal
#' @noRd
.scale_excel_sheet_reads <- function(n, max_sheet_reads) {
  safe_n <- max(1L, suppressWarnings(as.integer(n)))
  safe_max <- max(1L, suppressWarnings(as.integer(max_sheet_reads)))
  return(max(1L, min(safe_max, safe_n)))
}

#' @title Build synthetic Excel fixture sheet
#' @description Build deterministic worksheet contents for synthetic benchmark
#'   workbooks.
#' @param n_rows Integer scalar rows per worksheet.
#' @param workbook_id Integer scalar workbook index.
#' @param sheet_id Integer scalar worksheet index.
#' @return A data.frame with stable schema and deterministic values.
#' @keywords internal
#' @noRd
.build_excel_fixture_sheet <- function(n_rows, workbook_id, sheet_id) {
  row_id <- seq_len(n_rows)
  continents <- c("asia", "europe", "africa", "americas", "oceania")

  data.frame(
    commodity = sprintf(
      "commodity_%02d",
      ((row_id + workbook_id + sheet_id - 1L) %% 12L) + 1L
    ),
    variable = sprintf(
      "variable_%02d",
      ((row_id + sheet_id - 1L) %% 6L) + 1L
    ),
    unit = ifelse(row_id %% 2L == 0L, "tonnes", "kg"),
    continent = continents[
      ((row_id + workbook_id - 1L) %% length(continents)) + 1L
    ],
    country = sprintf(
      "country_%02d",
      ((row_id + workbook_id + sheet_id - 1L) %% 25L) + 1L
    ),
    value = as.character((row_id * (sheet_id + 1L) + workbook_id) %% 10000L),
    stringsAsFactors = FALSE
  )
}

#' @title Create synthetic Excel benchmark fixtures
#' @description Create a deterministic fixture directory containing synthetic
#'   xlsx files with controlled workbook count and worksheet row count.
#' @param workbook_count Integer scalar number of workbooks to create.
#' @param rows_per_sheet Integer scalar rows per worksheet.
#' @param sheet_count Integer scalar worksheets per workbook.
#' @return Character scalar fixture directory path.
#' @keywords internal
#' @noRd
.create_excel_benchmark_fixture_dir <- function(
  workbook_count,
  rows_per_sheet,
  sheet_count = 2L
) {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    stop("writexl package is required for synthetic Excel benchmark fixtures")
  }

  safe_workbook_count <- max(1L, suppressWarnings(as.integer(workbook_count)))
  safe_rows <- max(1L, suppressWarnings(as.integer(rows_per_sheet)))
  safe_sheet_count <- max(1L, suppressWarnings(as.integer(sheet_count)))

  fixture_root <- file.path(tempdir(), "perf_excel_fixture_generated")
  fixture_dir <- file.path(
    fixture_root,
    sprintf(
      "wb_%03d_rows_%05d_sheets_%02d",
      safe_workbook_count,
      safe_rows,
      safe_sheet_count
    )
  )

  existing_files <- character(0)
  if (dir.exists(fixture_dir)) {
    existing_files <- fs::dir_ls(
      path = fixture_dir,
      type = "file",
      recurse = FALSE,
      glob = "*.xlsx"
    )
  }

  if (length(existing_files) == safe_workbook_count) {
    return(fixture_dir)
  }

  if (dir.exists(fixture_dir)) {
    unlink(fixture_dir, recursive = TRUE, force = TRUE)
  }
  dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)

  for (workbook_i in seq_len(safe_workbook_count)) {
    workbook_path <- file.path(
      fixture_dir,
      sprintf("perf_fixture_%03d.xlsx", workbook_i)
    )
    sheet_payload <- lapply(seq_len(safe_sheet_count), function(sheet_i) {
      .build_excel_fixture_sheet(
        n_rows = safe_rows,
        workbook_id = workbook_i,
        sheet_id = sheet_i
      )
    })
    names(sheet_payload) <- sprintf("sheet_%02d", seq_len(safe_sheet_count))
    writexl::write_xlsx(sheet_payload, path = workbook_path)
  }

  return(fixture_dir)
}

#' @title Resolve benchmark Excel file paths
#' @description Discover benchmark fixture files and return existing paths.
#' @param read_cfg Named list config for import readers.
#' @return Character vector of existing xlsx paths.
#' @keywords internal
#' @noRd
.resolve_excel_benchmark_read_paths <- function(read_cfg) {
  file_meta <- discover_pipeline_files(read_cfg)
  available_paths <- as.character(file_meta$file_path)
  available_paths <- available_paths[file.exists(available_paths)]
  return(as.character(available_paths))
}

#' @title Build Excel sheet reference table
#' @description Enumerate available workbook/sheet pairs for deterministic
#'   per-sheet read workloads.
#' @param file_paths Character vector of xlsx paths.
#' @return data.table with columns file_path and sheet_name.
#' @keywords internal
#' @noRd
.build_excel_sheet_reference_table <- function(file_paths) {
  if (length(file_paths) == 0L) {
    return(data.table::data.table(
      file_path = character(),
      sheet_name = character()
    ))
  }

  refs <- lapply(as.character(file_paths), function(path_i) {
    sheet_names <- readxl::excel_sheets(path_i)
    if (length(sheet_names) == 0L) {
      return(data.table::data.table(
        file_path = character(),
        sheet_name = character()
      ))
    }
    data.table::data.table(
      file_path = rep(path_i, length(sheet_names)),
      sheet_name = as.character(sheet_names)
    )
  })

  data.table::rbindlist(refs, use.names = TRUE, fill = TRUE)
}

#' @title Build read benchmark config
#' @description Build a config object compatible with discover/read import
#'   helpers while preserving commodityion defaults when available.
#' @param cfg A named list from get_analysis_config().
#' @param import_folder Character scalar folder path.
#' @return Named list config for import read helpers.
#' @keywords internal
#' @noRd
.build_excel_read_benchmark_config <- function(cfg, import_folder) {
  pipeline_cfg <- NULL

  if (exists("load_pipeline_config", mode = "function")) {
    pipeline_cfg <- tryCatch(
      load_pipeline_config(),
      error = function(e) NULL
    )
  }

  default_cfg <- make_benchmark_config()
  read_cfg <- if (is.list(pipeline_cfg)) pipeline_cfg else default_cfg

  if (
    is.null(read_cfg$column_required) ||
      !is.character(read_cfg$column_required) ||
      length(read_cfg$column_required) == 0L
  ) {
    read_cfg$column_required <- default_cfg$column_required
  }

  if (is.null(read_cfg$paths)) {
    read_cfg$paths <- list()
  }
  if (is.null(read_cfg$paths$data)) {
    read_cfg$paths$data <- list()
  }
  if (is.null(read_cfg$paths$data$import)) {
    read_cfg$paths$data$import <- list()
  }
  read_cfg$paths$data$import$raw <- import_folder

  return(read_cfg)
}

# ── 5a. stage 0 — general pipeline ──────────────────────────────────────────

#' @title Build stage 0 benchmarks
#' @description Internal builder for stage 0 benchmark descriptors.
#' @param cfg A named list from get_analysis_config().
#' @return A list of benchmark descriptors.
#' @keywords internal
#' @noRd
.build_stage_0_general_benchmarks <- function(cfg) {
  na_frac <- cfg$na_fraction
  list(
    list(
      name = "normalize_string_impl",
      stage = "0-general",
      description = "normalise a character vector of length n to ASCII lowercase",
      fn_factory = function(n) {
        x <- paste0(
          sample(LETTERS, n, replace = TRUE),
          sample(0:9, n, replace = TRUE),
          sample(
            c("\u00e9", "\u00f1", "\u00fc", " ", "-", "_"),
            n,
            replace = TRUE
          )
        )
        function() normalize_string_impl(x)
      }
    ),

    list(
      name = "coerce_numeric_safe",
      stage = "0-general",
      description = "coerce a character vector of length n to numeric",
      fn_factory = function(n) {
        x <- make_numeric_string_vec(n)
        function() coerce_numeric_safe(x)
      }
    ),

    list(
      name = "drop_na_value_rows",
      stage = "0-general",
      description = paste0(
        "filter NA-value rows from a data.table of n rows (",
        round(na_frac * 100L),
        "% NA)"
      ),
      fn_factory = function(n) {
        dt <- make_long_dt(n, na_fraction = na_frac)
        function() drop_na_value_rows(dt)
      }
    )
  )
}

# ── 5b. stage 1 — import pipeline ────────────────────────────────────────────

#' @title Build stage 1 benchmarks
#' @description Internal builder for stage 1 benchmark descriptors.
#' @param cfg A named list from get_analysis_config().
#' @return A list of benchmark descriptors.
#' @keywords internal
#' @noRd
.build_stage_1_import_benchmarks <- function(cfg) {
  n_yrs <- cfg$n_year_cols
  dup_frac <- cfg$dup_fraction
  bench_cfg <- make_benchmark_config()
  excel_fixture_sheet_count <- max(
    1L,
    .resolve_integer_cfg(cfg$excel_fixture_sheet_count, fallback = 2L)
  )
  excel_fixture_base_rows_per_sheet <- max(
    8L,
    .resolve_integer_cfg(cfg$excel_fixture_base_rows_per_sheet, fallback = 16L)
  )
  excel_discovery_scale_divisor <- max(
    1L,
    .resolve_integer_cfg(cfg$excel_discovery_scale_divisor, fallback = 500L)
  )
  excel_discovery_max_workbooks <- max(
    1L,
    .resolve_integer_cfg(cfg$excel_discovery_max_workbooks, fallback = 96L)
  )
  excel_discovery_repeats_per_iteration <- max(
    1L,
    .resolve_integer_cfg(
      cfg$excel_discovery_repeats_per_iteration,
      fallback = 20L
    )
  )
  excel_read_workbook_count <- max(
    1L,
    .resolve_integer_cfg(cfg$excel_read_workbook_count, fallback = 4L)
  )
  excel_read_rows_per_sheet <- max(
    1L,
    .resolve_integer_cfg(cfg$excel_read_rows_per_sheet, fallback = 128L)
  )
  excel_read_max_sheet_reads_per_iteration <- max(
    1L,
    .resolve_integer_cfg(
      cfg$excel_read_max_sheet_reads_per_iteration,
      fallback = 1000L
    )
  )
  excel_read_repeats_per_iteration <- max(
    1L,
    .resolve_integer_cfg(cfg$excel_read_repeats_per_iteration, fallback = 2L)
  )

  list(
    list(
      name = "normalize_key_fields",
      stage = "1-import",
      description = "normalize commodity/variable/continent/country in n-row wide table",
      fn_factory = function(n) {
        df <- make_wide_dt(n, n_years = n_yrs)
        function() {
          normalize_key_fields(data.table::copy(df), "cereals", bench_cfg)
        }
      }
    ),

    list(
      name = "reshape_to_long",
      stage = "1-import",
      description = paste0(
        "melt n-row wide table (",
        n_yrs,
        " year cols) to long format"
      ),
      fn_factory = function(n) {
        df <- make_wide_dt(n, n_years = n_yrs)
        attr(df, "whep_year_columns") <- identify_year_columns(df, bench_cfg)
        function() reshape_to_long(df, bench_cfg)
      }
    ),

    list(
      name = "validate_mandatory_fields_dt",
      stage = "1-import",
      description = "check mandatory non-empty fields in n-row long table",
      fn_factory = function(n) {
        dt <- make_long_dt(n, na_fraction = 0.05)
        function() validate_mandatory_fields_dt(dt, bench_cfg)
      }
    ),

    list(
      name = "detect_duplicates_dt",
      stage = "1-import",
      description = paste0(
        "detect duplicate keys in n-row long table (",
        round(dup_frac * 100L),
        "% dups)"
      ),
      fn_factory = function(n) {
        dt <- make_long_dt(n, dup_fraction = dup_frac)
        function() detect_duplicates_dt(dt)
      }
    ),

    list(
      name = "consolidate_audited_dt",
      stage = "1-import",
      description = "consolidate and reorder columns in a list of n-row long tables",
      fn_factory = function(n) {
        chunk <- max(1L, n %/% 3L)
        dt_list <- list(
          make_long_dt(chunk),
          make_long_dt(chunk),
          make_long_dt(n - 2L * chunk)
        )
        local_cfg <- bench_cfg
        function() {
          consolidate_audited_dt(dt_list, local_cfg)
        }
      }
    ),

    list(
      name = "discover_excel_files",
      stage = "1-import",
      description = paste0(
        "discover synthetic xlsx files with n-scaled workbook count ",
        "and fixed worksheet size across repeated discovery passes"
      ),
      complexity_n_transform = function(n_values) {
        vapply(
          n_values,
          function(n_i) {
            .scale_excel_discovery_workbook_count(
              n = n_i,
              max_workbooks = excel_discovery_max_workbooks,
              scale_divisor = excel_discovery_scale_divisor
            )
          },
          integer(1)
        )
      },
      fn_factory = function(n) {
        workbook_count <- .scale_excel_discovery_workbook_count(
          n = n,
          max_workbooks = excel_discovery_max_workbooks,
          scale_divisor = excel_discovery_scale_divisor
        )
        import_folder <- .create_excel_benchmark_fixture_dir(
          workbook_count = workbook_count,
          rows_per_sheet = excel_fixture_base_rows_per_sheet,
          sheet_count = excel_fixture_sheet_count
        )
        read_cfg <- .build_excel_read_benchmark_config(cfg, import_folder)

        function() {
          discovered_rows <- integer(excel_discovery_repeats_per_iteration)
          for (iter_i in seq_len(excel_discovery_repeats_per_iteration)) {
            file_meta <- discover_pipeline_files(read_cfg)
            discovered_rows[[iter_i]] <- as.integer(nrow(file_meta))
          }
          return(invisible(sum(discovered_rows)))
        }
      }
    ),

    list(
      name = "read_excel_file_sheets",
      stage = "1-import",
      description = paste0(
        "read n synthetic workbook sheets (fixed rows per sheet) where n ",
        "directly represents total sheet reads per timed invocation"
      ),
      complexity_min_best_r2 = -1,
      complexity_n_transform = function(n_values) {
        vapply(
          n_values,
          function(n_i) {
            .scale_excel_sheet_reads(
              n = n_i,
              max_sheet_reads = excel_read_max_sheet_reads_per_iteration
            )
          },
          integer(1)
        )
      },
      fn_factory = function(n) {
        sheet_reads_target <- .scale_excel_sheet_reads(
          n = n,
          max_sheet_reads = excel_read_max_sheet_reads_per_iteration
        )

        workbook_count_target <- max(
          excel_read_workbook_count,
          as.integer(ceiling(sheet_reads_target / excel_fixture_sheet_count))
        )

        import_folder <- .create_excel_benchmark_fixture_dir(
          workbook_count = workbook_count_target,
          rows_per_sheet = excel_read_rows_per_sheet,
          sheet_count = excel_fixture_sheet_count
        )
        read_cfg <- .build_excel_read_benchmark_config(cfg, import_folder)
        available_paths <- .resolve_excel_benchmark_read_paths(read_cfg)
        sheet_refs <- .build_excel_sheet_reference_table(available_paths)

        workbook_sheet_map <- if (nrow(sheet_refs) > 0L) {
          split(
            as.character(sheet_refs$sheet_name),
            as.character(sheet_refs$file_path)
          )
        } else {
          list()
        }

        workbook_reads_target <- max(
          1L,
          as.integer(ceiling(sheet_reads_target / excel_fixture_sheet_count))
        )

        selected_workbooks <- if (length(available_paths) > 0L) {
          available_paths[seq_len(min(
            workbook_reads_target,
            length(available_paths)
          ))]
        } else {
          character(0)
        }

        function() {
          if (length(selected_workbooks) == 0L) {
            return(invisible(list(
              rows = 0L,
              errors = 0L,
              sheet_reads = 0L,
              workbook_reads = 0L
            )))
          }

          total_rows <- 0L
          total_errors <- 0L
          total_workbook_reads <- 0L

          for (iter_i in seq_len(excel_read_repeats_per_iteration)) {
            iter_idx <- seq(
              from = iter_i,
              to = length(selected_workbooks),
              by = excel_read_repeats_per_iteration
            )
            if (length(iter_idx) == 0L) {
              next
            }

            workbook_batch_paths <- selected_workbooks[iter_idx]
            batch_result <- read_workbook_batch(
              file_paths = workbook_batch_paths,
              config = read_cfg,
              sheet_names_by_file = workbook_sheet_map
            )

            total_rows <- total_rows +
              sum(vapply(
                batch_result$read_data_list,
                function(dt_i) {
                  as.integer(nrow(dt_i))
                },
                integer(1)
              ))

            total_errors <- total_errors +
              as.integer(length(batch_result$errors))
            total_workbook_reads <- total_workbook_reads +
              length(workbook_batch_paths)
          }

          total_sheet_reads <- as.integer(
            total_workbook_reads * excel_fixture_sheet_count
          )

          return(invisible(list(
            rows = total_rows,
            errors = total_errors,
            sheet_reads = total_sheet_reads,
            workbook_reads = total_workbook_reads
          )))
        }
      }
    )
  )
}

# ── 5c. stage 2 — post-processing pipeline ───────────────────────────────────

#' @title Build stage 2 benchmarks
#' @description Internal builder for stage 2 benchmark descriptors.
#' @param cfg A named list from get_analysis_config().
#' @return A list of benchmark descriptors.
#' @keywords internal
#' @noRd
.build_stage_2_postpro_benchmarks <- function(cfg) {
  dup_frac <- cfg$dup_fraction
  na_frac <- cfg$na_fraction

  conversion_rules_raw <- data.table::data.table(
    commodity_key = rep(.ca_commodity, each = 3L),
    unit_source = rep(
      c("tonnes", "kg_ha", "ha"),
      times = length(.ca_commodity)
    ),
    unit_target = rep(
      c("kg", "kg_per_ha_std", "ha_std"),
      times = length(.ca_commodity)
    ),
    unit_factor = rep(c(1000, 1, 1), times = length(.ca_commodity)),
    unit_offset = 0
  )

  list(
    list(
      name = "apply_standardize_rules",
      stage = "2-postpro",
      description = paste0(
        "apply prepared unit conversion rules to an n-row long table (",
        round(na_frac * 100L),
        "% NA values, ",
        round(dup_frac * 100L),
        "% duplicates)"
      ),
      fn_factory = function(n) {
        dt_raw <- make_long_dt(
          n,
          na_fraction = na_frac,
          dup_fraction = dup_frac
        )
        prepared_rules <- prepare_standardize_rules(conversion_rules_raw)
        function() {
          apply_standardize_rules(
            mapped_dt = dt_raw,
            prepared_rules_dt = prepared_rules,
            unit_column = "unit",
            value_column = "value",
            commodity_column = "commodity"
          )
        }
      }
    ),

    list(
      name = "extract_aggregated_rows",
      stage = "2-postpro",
      description = paste0(
        "extract duplicate groups from n-row standardized table (",
        round(dup_frac * 100L),
        "% duplicates)"
      ),
      fn_factory = function(n) {
        dt_raw <- make_long_dt(n, dup_fraction = dup_frac)
        dt_raw[, value := suppressWarnings(as.numeric(value))]
        function() extract_aggregated_rows(data.table::copy(dt_raw))
      }
    ),

    list(
      name = "aggregate_standardized_rows",
      stage = "2-postpro",
      description = paste0(
        "group-sum n rows by all non-value columns (",
        round(dup_frac * 100L),
        "% duplicates to aggregate)"
      ),
      fn_factory = function(n) {
        dt_raw <- make_long_dt(n, dup_fraction = dup_frac)
        dt_raw[, value := suppressWarnings(as.numeric(value))]
        function() aggregate_standardized_rows(data.table::copy(dt_raw))
      }
    )
  )
}

# ── 5d. stage 3 — export pipeline ────────────────────────────────────────────

#' @title Build stage 3 benchmarks
#' @description Internal builder for stage 3 benchmark descriptors.
#' @param cfg A named list from get_analysis_config().
#' @return A list of benchmark descriptors.
#' @keywords internal
#' @noRd
.build_stage_3_export_benchmarks <- function(cfg) {
  list(
    list(
      name = "compute_unique_column_values",
      stage = "3-export",
      description = "compute sorted unique values for one column of n-row table",
      fn_factory = function(n) {
        dt <- make_long_dt(n)
        function() compute_unique_column_values(dt, "country")
      }
    ),

    list(
      name = "normalize_for_comparison",
      stage = "3-export",
      description = "deep-copy, drop year col, sort columns and rows of n-row table",
      fn_factory = function(n) {
        dt <- make_long_dt(n)
        function() normalize_for_comparison(data.table::copy(dt))
      }
    )
  )
}

# ── 5e. public builders ───────────────────────────────────────────────────────

#' @title Build stage benchmarks
#' @description Return benchmark descriptors for one pipeline stage.
#' @param stage_id A character scalar stage identifier.
#' @param cfg A named list from get_analysis_config().
#' @return A named list of benchmark descriptors.
build_stage_benchmarks <- function(stage_id, cfg) {
  benchmarks <- switch(
    stage_id,
    "0-general" = .build_stage_0_general_benchmarks(cfg),
    "1-import" = .build_stage_1_import_benchmarks(cfg),
    "2-postpro" = .build_stage_2_postpro_benchmarks(cfg),
    "3-export" = .build_stage_3_export_benchmarks(cfg),
    stop(sprintf("unknown stage_id: '%s'", stage_id))
  )
  names(benchmarks) <- vapply(benchmarks, function(b) b$name, character(1))
  return(benchmarks)
}

#' @title Build benchmark definitions
#' @description Return the full benchmark descriptor catalog across configured
#'   stages.
#' @param cfg A named list from get_analysis_config().
#' @return A named list of benchmark descriptors.
build_benchmark_definitions <- function(cfg) {
  set.seed(cfg$rng_seed)
  all_benchmarks <- lapply(cfg$stages, build_stage_benchmarks, cfg = cfg)
  combined <- do.call(c, all_benchmarks)
  names(combined) <- vapply(combined, function(b) b$name, character(1))
  return(combined)
}

#' @title Build all benchmarks
#' @description Alias for build_benchmark_definitions().
#' @param cfg A named list from get_analysis_config().
#' @return A named list of benchmark descriptors.
build_all_benchmarks <- function(cfg) build_benchmark_definitions(cfg)
