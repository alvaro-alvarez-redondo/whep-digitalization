# tests/perf/test-big-o-estimation.R
# unit tests for the perf module.
#
# the module is split into modular scripts (p0-dependencies.R ... p9-orchestration.R)
# sourced by perf/p9-orchestration.R. this test file
# sources the master script, which loads all sub-modules and exposes the
# full public API.
#
# covers: config helpers, synthetic data generators, complexity model fitting,
# benchmark summary statistics, and Markdown serialisation.

source(here::here("tests", "test_helper.R"), echo = FALSE)
source(
  here::here("perf", "perf_pipeline", "p9-orchestration.R"),
  echo = FALSE
)


# ── get_analysis_config ──────────────────────────────────────────────────────────

testthat::test_that("get_analysis_config returns a list with all required fields", {
  cfg <- get_analysis_config()

  testthat::expect_type(cfg, "list")
  testthat::expect_true("input_sizes" %in% names(cfg))
  testthat::expect_true("n_reps" %in% names(cfg))
  testthat::expect_true("n_year_cols" %in% names(cfg))
  testthat::expect_true("excel_fixture_sheet_count" %in% names(cfg))
  testthat::expect_true("excel_fixture_base_rows_per_sheet" %in% names(cfg))
  testthat::expect_true("excel_discovery_scale_divisor" %in% names(cfg))
  testthat::expect_true("excel_discovery_max_workbooks" %in% names(cfg))
  testthat::expect_true("excel_discovery_repeats_per_iteration" %in% names(cfg))
  testthat::expect_true("excel_read_workbook_count" %in% names(cfg))
  testthat::expect_true("excel_read_rows_per_sheet" %in% names(cfg))
  testthat::expect_true(
    "excel_read_max_sheet_reads_per_iteration" %in% names(cfg)
  )
  testthat::expect_true("excel_read_repeats_per_iteration" %in% names(cfg))
  testthat::expect_true("complexity_r2_tolerance" %in% names(cfg))
  testthat::expect_true("complexity_min_best_r2" %in% names(cfg))
  testthat::expect_true("complexity_min_unique_n" %in% names(cfg))
  testthat::expect_true("complexity_min_n_span_ratio" %in% names(cfg))
  testthat::expect_true("na_fraction" %in% names(cfg))
  testthat::expect_true("dup_fraction" %in% names(cfg))
  testthat::expect_true("rng_seed" %in% names(cfg))
  testthat::expect_true("produce_plots" %in% names(cfg))
  testthat::expect_true("quiet" %in% names(cfg))
})

testthat::test_that("get_analysis_config input_sizes are positive integers", {
  cfg <- get_analysis_config()
  testthat::expect_true(all(cfg$input_sizes > 0L))
  testthat::expect_true(is.integer(cfg$input_sizes))
})

testthat::test_that("get_analysis_config fractions are in [0, 1]", {
  cfg <- get_analysis_config()
  testthat::expect_true(cfg$na_fraction >= 0 & cfg$na_fraction <= 1)
  testthat::expect_true(cfg$dup_fraction >= 0 & cfg$dup_fraction <= 1)
})

testthat::test_that("get_analysis_config includes valid complexity tuning fields", {
  cfg <- get_analysis_config()
  testthat::expect_true(cfg$complexity_r2_tolerance >= 0)
  testthat::expect_true(cfg$complexity_min_best_r2 <= 1)
  testthat::expect_true(cfg$complexity_min_unique_n >= 3L)
  testthat::expect_true(cfg$complexity_min_n_span_ratio > 1)
  testthat::expect_true(cfg$excel_discovery_repeats_per_iteration >= 1L)
  testthat::expect_true(cfg$excel_read_max_sheet_reads_per_iteration >= 1L)
  testthat::expect_true(cfg$excel_read_max_sheet_reads_per_iteration >= 1000L)
  testthat::expect_true(cfg$excel_read_repeats_per_iteration >= 1L)
})


# ── build_perf_run_config ─────────────────────────────────────────────────────

testthat::test_that("build_perf_run_config appends preset-specific output subdir", {
  cfg <- build_perf_run_config(preset_name = "quick")

  testthat::expect_equal(cfg$preset_name, "quick")
  testthat::expect_equal(basename(cfg$output_dir), "perf_diagnosis_quick")
  testthat::expect_equal(basename(dirname(cfg$output_dir)), "perf_diagnosis")
})

testthat::test_that("build_perf_run_config applies preset subdir after output override", {
  root_dir <- tempfile("perf_reports_root_")
  cfg <- build_perf_run_config(
    preset_name = "medium",
    overrides = list(output_dir = root_dir)
  )

  testthat::expect_equal(cfg$preset_name, "medium")
  testthat::expect_equal(
    cfg$output_dir,
    file.path(root_dir, "perf_diagnosis_medium")
  )
})


# ── make_benchmark_config ─────────────────────────────────────────────────────

testthat::test_that("make_benchmark_config contains required column specs", {
  cfg <- make_benchmark_config()

  testthat::expect_type(cfg, "list")
  testthat::expect_true("column_required" %in% names(cfg))
  testthat::expect_true("column_id" %in% names(cfg))
  testthat::expect_true("column_order" %in% names(cfg))
  testthat::expect_true("defaults" %in% names(cfg))
})

testthat::test_that("make_benchmark_config column_order includes full target schema", {
  cfg <- make_benchmark_config()
  # consolidate_audited_dt checks that all of these are in column_order
  required_schema <- c(
    "hemisphere",
    "continent",
    "country",
    "commodity",
    "variable",
    "unit",
    "year",
    "value",
    "notes",
    "footnotes",
    "yearbook",
    "document"
  )
  testthat::expect_true(
    all(required_schema %in% cfg$column_order),
    info = paste(
      "missing:",
      paste(setdiff(required_schema, cfg$column_order), collapse = ", ")
    )
  )
})

testthat::test_that("make_benchmark_config column_order has no duplicates", {
  cfg <- make_benchmark_config()
  testthat::expect_equal(
    length(cfg$column_order),
    length(unique(cfg$column_order))
  )
})


# ── make_wide_dt ──────────────────────────────────────────────────────────────

testthat::test_that("make_wide_dt returns data.table with correct row count", {
  dt <- make_wide_dt(200L)
  testthat::expect_true(data.table::is.data.table(dt))
  testthat::expect_equal(nrow(dt), 200L)
})

testthat::test_that("make_wide_dt returns correct number of year columns", {
  dt <- make_wide_dt(50L, n_years = 5L)
  year_cols <- grep("^\\d{4}$", names(dt), value = TRUE)
  testthat::expect_equal(length(year_cols), 5L)
})

testthat::test_that("make_wide_dt year column names are sequential years", {
  dt <- make_wide_dt(10L, n_years = 3L)
  year_cols <- grep("^\\d{4}$", names(dt), value = TRUE)
  testthat::expect_equal(sort(year_cols), c("2000", "2001", "2002"))
})

testthat::test_that("make_wide_dt contains required base columns", {
  dt <- make_wide_dt(20L)
  required <- c(
    "commodity",
    "variable",
    "unit",
    "continent",
    "country",
    "footnotes"
  )
  testthat::expect_true(all(required %in% names(dt)))
})


# ── make_long_dt ──────────────────────────────────────────────────────────────

testthat::test_that("make_long_dt returns data.table with correct row count", {
  dt <- make_long_dt(300L)
  testthat::expect_true(data.table::is.data.table(dt))
  testthat::expect_equal(nrow(dt), 300L)
})

testthat::test_that("make_long_dt contains full long-format schema columns", {
  dt <- make_long_dt(10L)
  required <- c(
    "commodity",
    "variable",
    "unit",
    "continent",
    "country",
    "year",
    "value",
    "notes",
    "yearbook",
    "document",
    "footnotes"
  )
  testthat::expect_true(all(required %in% names(dt)))
})

testthat::test_that("make_long_dt respects na_fraction", {
  set.seed(1L)
  dt <- make_long_dt(2000L, na_fraction = 0.5)
  na_share <- mean(is.na(dt$value))
  # allow generous tolerance due to random sampling
  testthat::expect_true(na_share > 0.3 & na_share < 0.7)
})

testthat::test_that("make_long_dt respects dup_fraction", {
  set.seed(2L)
  n <- 1000L
  dt <- make_long_dt(n, dup_fraction = 0.2)
  # total rows should equal n
  testthat::expect_equal(nrow(dt), n)
})


# ── make_numeric_string_vec ───────────────────────────────────────────────────

testthat::test_that("make_numeric_string_vec returns character vector of length n", {
  vec <- make_numeric_string_vec(150L)
  testthat::expect_type(vec, "character")
  testthat::expect_equal(length(vec), 150L)
})

testthat::test_that("make_numeric_string_vec contains mix of valid numerics, empty, NA", {
  set.seed(7L)
  vec <- make_numeric_string_vec(500L)
  has_na <- any(is.na(vec))
  has_empty <- any(vec == "", na.rm = TRUE)
  has_num <- any(!is.na(suppressWarnings(as.numeric(vec[!is.na(vec)]))))
  testthat::expect_true(has_na)
  testthat::expect_true(has_empty)
  testthat::expect_true(has_num)
})


# ── fit_complexity_model ──────────────────────────────────────────────────────

testthat::test_that("fit_complexity_model identifies O(1) from flat data", {
  set.seed(10L)
  n <- c(100, 500, 1000, 2500, 5000, 10000, 25000, 50000)
  t <- rep(0.01, length(n)) + stats::rnorm(length(n), 0, 0.0001)
  fit <- fit_complexity_model(n, t)

  testthat::expect_type(fit, "list")
  testthat::expect_true("best_class" %in% names(fit))
  testthat::expect_equal(fit$best_class, "O(1)")
})

testthat::test_that("fit_complexity_model identifies O(n) from linear data", {
  n <- c(100, 500, 1000, 2500, 5000, 10000, 25000, 50000)
  t <- 2e-6 * n + 0.001
  fit <- fit_complexity_model(n, t)

  testthat::expect_equal(fit$best_class, "O(n)")
  testthat::expect_true(!is.na(fit$best_r2))
  testthat::expect_true(fit$best_r2 > 0.99)
})

testthat::test_that("fit_complexity_model identifies O(n^2) from quadratic data", {
  n <- c(100, 500, 1000, 2500, 5000, 10000)
  t <- 1e-10 * n^2 + 0.0005
  fit <- fit_complexity_model(n, t)

  testthat::expect_equal(fit$best_class, "O(n^2)")
  testthat::expect_true(fit$best_r2 > 0.99)
})

testthat::test_that("fit_complexity_model returns 'unknown' with too few points", {
  fit <- fit_complexity_model(c(100, 200), c(0.01, 0.02))
  testthat::expect_equal(fit$best_class, "unknown")
  testthat::expect_true(is.na(fit$best_r2))
})

testthat::test_that("fit_complexity_model returns all_r2 named vector", {
  n <- c(100, 500, 1000, 2500, 5000, 10000)
  t <- 1e-6 * n + 0.001
  fit <- fit_complexity_model(n, t)

  testthat::expect_type(fit$all_r2, "double")
  testthat::expect_equal(
    sort(names(fit$all_r2)),
    sort(c("O(1)", "O(log n)", "O(n)", "O(n log n)", "O(n^2)", "O(n^3)"))
  )
})

testthat::test_that("fit_complexity_model handles NA and negative times gracefully", {
  n <- c(100, 500, 1000, NA, 5000, 10000)
  t <- c(0.001, 0.005, 0.010, NA, 0.050, 0.100)
  fit <- fit_complexity_model(n, t)

  testthat::expect_type(fit$best_class, "character")
  testthat::expect_length(fit$best_class, 1L)
})

testthat::test_that("fit_complexity_model breaks ties toward simpler class", {
  candidate_env <- environment(fit_complexity_model)
  original_candidates <- get("get_complexity_candidates", envir = candidate_env)
  on.exit(
    assign(
      "get_complexity_candidates",
      original_candidates,
      envir = candidate_env
    ),
    add = TRUE
  )

  assign(
    "get_complexity_candidates",
    function() {
      list(
        list(label = "O(n)", f = function(n) n),
        list(label = "O(n log n)", f = function(n) n)
      )
    },
    envir = candidate_env
  )

  n <- c(100, 500, 1000, 2500, 5000)
  t <- 1e-6 * n + 0.001
  fit <- fit_complexity_model(n, t, r2_tolerance = 0)

  testthat::expect_equal(fit$best_class, "O(n)")
})

testthat::test_that("fit_complexity_model validates r2_tolerance", {
  n <- c(100, 500, 1000)
  t <- c(0.01, 0.05, 0.1)

  testthat::expect_error(
    fit_complexity_model(n, t, r2_tolerance = -0.1),
    "r2_tolerance"
  )
})

testthat::test_that("fit_complexity_model returns unknown when distinct n support is insufficient", {
  n <- c(100, 100, 100, 200, 200, 200, 300, 300)
  t <- c(0.10, 0.11, 0.12, 0.20, 0.21, 0.22, 0.30, 0.31)

  fit <- fit_complexity_model(
    n_values = n,
    t_values = t,
    min_unique_n = 4L,
    min_n_span_ratio = 2
  )

  testthat::expect_equal(fit$best_class, "unknown")
  testthat::expect_true(is.na(fit$best_r2))
})

testthat::test_that("fit_complexity_model returns unknown when n span ratio is too flat", {
  n <- c(100, 110, 120, 130, 140)
  t <- c(0.10, 0.11, 0.12, 0.13, 0.14)

  fit <- fit_complexity_model(
    n_values = n,
    t_values = t,
    min_unique_n = 5L,
    min_n_span_ratio = 2
  )

  testthat::expect_equal(fit$best_class, "unknown")
  testthat::expect_true(is.na(fit$best_r2))
})

testthat::test_that("fit_complexity_model validates support threshold arguments", {
  n <- c(100, 500, 1000, 2500, 5000)
  t <- c(0.01, 0.05, 0.10, 0.25, 0.50)

  testthat::expect_error(
    fit_complexity_model(n, t, min_unique_n = 2L),
    "min_unique_n"
  )
  testthat::expect_error(
    fit_complexity_model(n, t, min_n_span_ratio = 1),
    "min_n_span_ratio"
  )
  testthat::expect_error(
    fit_complexity_model(n, t, min_best_r2 = 2),
    "min_best_r2"
  )
})

testthat::test_that(".has_complexity_fit_support validates uniqueness and span", {
  testthat::expect_true(
    .has_complexity_fit_support(
      n_values = c(100, 500, 1000, 2500, 5000),
      min_unique_n_req = 3L,
      min_n_span_ratio_req = 2
    )
  )

  testthat::expect_false(
    .has_complexity_fit_support(
      n_values = c(100, 100, 100, 250, 250),
      min_unique_n_req = 3L,
      min_n_span_ratio_req = 2
    )
  )

  testthat::expect_false(
    .has_complexity_fit_support(
      n_values = c(100, 110, 120, 130, 140),
      min_unique_n_req = 3L,
      min_n_span_ratio_req = 2
    )
  )
})

testthat::test_that(".select_complexity_fit_n falls back when transformed n collapses support", {
  original_n <- c(100, 500, 1000, 2500, 5000, 10000, 25000, 50000)
  transformed_n <- c(100, 256, 256, 256, 256, 256, 256, 256)

  selected <- .select_complexity_fit_n(
    original_n = original_n,
    transformed_n = transformed_n,
    min_unique_n_req = 3L,
    min_n_span_ratio_req = 2
  )

  testthat::expect_identical(selected$source, "original")
  testthat::expect_true(selected$fallback_applied)
  testthat::expect_equal(selected$n_values, as.numeric(original_n))
})

testthat::test_that(".select_complexity_fit_n keeps transformed n when support is sufficient", {
  original_n <- c(100, 500, 1000, 2500, 5000, 10000, 25000, 50000)
  transformed_n <- c(100, 500, 1000, 1000, 1000, 1000, 1000, 1000)

  selected <- .select_complexity_fit_n(
    original_n = original_n,
    transformed_n = transformed_n,
    min_unique_n_req = 3L,
    min_n_span_ratio_req = 2
  )

  testthat::expect_identical(selected$source, "transformed")
  testthat::expect_false(selected$fallback_applied)
  testthat::expect_equal(selected$n_values, as.numeric(transformed_n))
})

testthat::test_that("fit_complexity_model returns unknown when best fit R2 is below threshold", {
  n <- c(100, 500, 1000, 2500, 5000, 10000)
  t <- c(0.10, 0.17, 0.14, 0.21, 0.18, 0.25)

  fit <- fit_complexity_model(
    n_values = n,
    t_values = t,
    min_best_r2 = 0.95,
    min_unique_n = 5L,
    min_n_span_ratio = 2
  )

  testthat::expect_equal(fit$best_class, "unknown")
  testthat::expect_true(is.na(fit$best_r2))
})


# ── summarise_benchmark ───────────────────────────────────────────────────────

testthat::test_that("summarise_benchmark returns correct per-n statistics", {
  raw_dt <- data.table::data.table(
    n = c(100L, 100L, 100L, 500L, 500L, 500L),
    rep = c(1L, 2L, 3L, 1L, 2L, 3L),
    elapsed_s = c(0.01, 0.02, 0.03, 0.05, 0.06, 0.07)
  )
  summ <- summarise_benchmark(raw_dt)

  testthat::expect_true(data.table::is.data.table(summ))
  testthat::expect_equal(nrow(summ), 2L)
  testthat::expect_true(all(
    c(
      "median_s",
      "mean_s",
      "sd_s",
      "min_s",
      "max_s",
      "iqr_s",
      "p95_s",
      "p99_s",
      "cv_s",
      "n_reps"
    ) %in%
      names(summ)
  ))
})

testthat::test_that("summarise_benchmark values are correct", {
  raw_dt <- data.table::data.table(
    n = c(100L, 100L, 100L),
    rep = 1L:3L,
    elapsed_s = c(0.01, 0.02, 0.03)
  )
  summ <- summarise_benchmark(raw_dt)

  testthat::expect_equal(summ$median_s, 0.02)
  testthat::expect_equal(summ$min_s, 0.01)
  testthat::expect_equal(summ$max_s, 0.03)
})

testthat::test_that("summarise_benchmark output is sorted by n", {
  raw_dt <- data.table::data.table(
    n = c(500L, 500L, 100L, 100L),
    rep = c(1L, 2L, 1L, 2L),
    elapsed_s = c(0.05, 0.06, 0.01, 0.02)
  )
  summ <- summarise_benchmark(raw_dt)
  testthat::expect_equal(summ$n, c(100L, 500L))
})

testthat::test_that("summarise_benchmark computes deterministic dispersion metrics", {
  raw_dt <- data.table::data.table(
    n = c(100L, 100L, 100L, 100L),
    rep = c(1L, 2L, 3L, 4L),
    elapsed_s = c(0.01, 0.02, 0.03, 0.04)
  )
  summ <- summarise_benchmark(raw_dt)

  testthat::expect_equal(summ$n_reps, 4L)
  testthat::expect_true(summ$iqr_s > 0)
  testthat::expect_true(summ$p95_s >= summ$median_s)
  testthat::expect_true(summ$p99_s >= summ$p95_s)
  testthat::expect_true(summ$cv_s > 0)
})


# ── build_benchmark_definitions ───────────────────────────────────────────────

testthat::test_that("build_benchmark_definitions returns a named list", {
  cfg <- utils::modifyList(
    get_analysis_config(),
    list(
      input_sizes = c(100L, 200L),
      n_reps = 1L
    )
  )
  defs <- build_benchmark_definitions(cfg)

  testthat::expect_type(defs, "list")
  testthat::expect_true(length(defs) > 0L)
  testthat::expect_false(is.null(names(defs)))
})

testthat::test_that("each benchmark definition has required fields", {
  cfg <- utils::modifyList(
    get_analysis_config(),
    list(
      input_sizes = c(100L),
      n_reps = 1L
    )
  )
  defs <- build_benchmark_definitions(cfg)

  for (nm in names(defs)) {
    bm <- defs[[nm]]
    testthat::expect_true("name" %in% names(bm), info = nm)
    testthat::expect_true("stage" %in% names(bm), info = nm)
    testthat::expect_true("description" %in% names(bm), info = nm)
    testthat::expect_true("fn_factory" %in% names(bm), info = nm)
    testthat::expect_type(bm$fn_factory, "closure")
  }
})

testthat::test_that("fn_factory returns a zero-argument function", {
  cfg <- utils::modifyList(
    get_analysis_config(),
    list(
      input_sizes = c(100L),
      n_reps = 1L
    )
  )
  defs <- build_benchmark_definitions(cfg)

  # test just the first benchmark to keep test fast
  bm <- defs[[1L]]
  fn <- bm$fn_factory(100L)
  testthat::expect_type(fn, "closure")
  testthat::expect_equal(length(formals(fn)), 0L)
})

testthat::test_that("stage 1 benchmark catalog includes split excel benchmarks", {
  cfg <- utils::modifyList(
    get_analysis_config(),
    list(
      stages = c("1-import"),
      input_sizes = c(100L),
      n_reps = 1L
    )
  )

  defs <- build_stage_benchmarks("1-import", cfg)

  testthat::expect_true("discover_excel_files" %in% names(defs))
  testthat::expect_true("read_excel_file_sheets" %in% names(defs))
  testthat::expect_identical(defs[["discover_excel_files"]]$stage, "1-import")
  testthat::expect_identical(defs[["read_excel_file_sheets"]]$stage, "1-import")
})

testthat::test_that("excel discovery workload scaling is bounded and deterministic", {
  scaled <- vapply(
    c(100L, 1000L, 5000L, 10000L, 50000L),
    function(n_i) {
      .scale_excel_discovery_workbook_count(
        n = n_i,
        max_workbooks = 64L,
        scale_divisor = 1000L
      )
    },
    integer(1)
  )

  testthat::expect_equal(scaled, c(1L, 1L, 5L, 10L, 50L))
})

testthat::test_that("excel sheet-read scaling is bounded and deterministic", {
  scaled <- vapply(
    c(100L, 1000L, 5000L, 10000L, 50000L),
    function(n_i) {
      .scale_excel_sheet_reads(
        n = n_i,
        max_sheet_reads = 5000L
      )
    },
    integer(1)
  )

  testthat::expect_equal(scaled, c(100L, 1000L, 5000L, 5000L, 5000L))
})

testthat::test_that("stage 1 excel benchmarks expose complexity input transforms", {
  cfg <- utils::modifyList(
    get_analysis_config(),
    list(
      stages = c("1-import"),
      input_sizes = c(100L),
      n_reps = 1L,
      excel_discovery_scale_divisor = 1000L,
      excel_discovery_max_workbooks = 64L,
      excel_read_rows_per_sheet = 128L,
      excel_read_max_sheet_reads_per_iteration = 5000L,
      excel_fixture_base_rows_per_sheet = 64L
    )
  )

  defs <- build_stage_benchmarks("1-import", cfg)
  discover_transform <- defs[["discover_excel_files"]]$complexity_n_transform
  read_transform <- defs[["read_excel_file_sheets"]]$complexity_n_transform

  testthat::expect_type(discover_transform, "closure")
  testthat::expect_type(read_transform, "closure")
  testthat::expect_equal(
    as.integer(discover_transform(c(100L, 1000L, 5000L, 10000L, 50000L))),
    c(1L, 1L, 5L, 10L, 50L)
  )
  testthat::expect_equal(
    as.integer(read_transform(c(100L, 1000L, 5000L, 10000L, 50000L))),
    c(100L, 1000L, 5000L, 5000L, 5000L)
  )
})

testthat::test_that("synthetic excel fixture generation scales count and size independently", {
  testthat::skip_if_not_installed("writexl")
  testthat::skip_if_not_installed("readxl")

  fixture_discovery <- .create_excel_benchmark_fixture_dir(
    workbook_count = 7L,
    rows_per_sheet = 64L,
    sheet_count = 2L
  )
  fixture_read <- .create_excel_benchmark_fixture_dir(
    workbook_count = 2L,
    rows_per_sheet = 512L,
    sheet_count = 2L
  )

  discovery_files <- fs::dir_ls(
    fixture_discovery,
    type = "file",
    glob = "*.xlsx"
  )
  read_files <- fs::dir_ls(fixture_read, type = "file", glob = "*.xlsx")

  testthat::expect_equal(length(discovery_files), 7L)
  testthat::expect_equal(length(read_files), 2L)

  read_sample <- readxl::read_excel(path = read_files[[1L]], sheet = "sheet_01")
  testthat::expect_equal(nrow(read_sample), 512L)
})

testthat::test_that("stage 1 split excel benchmark factories execute without error", {
  testthat::skip_if_not_installed("writexl")
  testthat::skip_if_not_installed("readxl")

  cfg <- utils::modifyList(
    get_analysis_config(),
    list(
      stages = c("1-import"),
      input_sizes = c(100L),
      n_reps = 1L,
      excel_discovery_scale_divisor = 1000L,
      excel_discovery_max_workbooks = 64L,
      excel_read_rows_per_sheet = 128L,
      excel_read_max_sheet_reads_per_iteration = 5000L,
      excel_read_workbook_count = 2L,
      excel_fixture_sheet_count = 2L,
      excel_fixture_base_rows_per_sheet = 64L
    )
  )

  defs <- build_stage_benchmarks("1-import", cfg)
  discover_fn <- defs[["discover_excel_files"]]$fn_factory(100L)
  read_fn <- defs[["read_excel_file_sheets"]]$fn_factory(100L)

  testthat::expect_type(discover_fn, "closure")
  testthat::expect_type(read_fn, "closure")
  testthat::expect_no_error(discover_fn())

  read_result <- NULL
  testthat::expect_no_error({
    read_result <- read_fn()
  })
  testthat::expect_type(read_result, "list")
  testthat::expect_equal(read_result$sheet_reads, 100L)
})

testthat::test_that("stage 2 benchmark catalog includes additional post-processing hotspots", {
  cfg <- utils::modifyList(
    get_analysis_config(),
    list(
      stages = c("2-postpro"),
      input_sizes = c(100L),
      n_reps = 1L
    )
  )

  defs <- build_benchmark_definitions(cfg)
  expected <- c(
    "apply_standardize_rules",
    "extract_aggregated_rows",
    "aggregate_standardized_rows"
  )

  testthat::expect_true(all(expected %in% names(defs)))
  testthat::expect_true(all(vapply(
    defs[expected],
    function(bm) identical(bm$stage, "2-postpro"),
    logical(1)
  )))
})

testthat::test_that("stage 2 benchmark factories execute without error", {
  cfg <- utils::modifyList(
    get_analysis_config(),
    list(
      stages = c("2-postpro"),
      input_sizes = c(100L),
      n_reps = 1L
    )
  )

  defs <- build_stage_benchmarks("2-postpro", cfg)
  expected <- c(
    "apply_standardize_rules",
    "extract_aggregated_rows",
    "aggregate_standardized_rows"
  )

  for (name_i in expected) {
    fn <- defs[[name_i]]$fn_factory(100L)
    testthat::expect_type(fn, "closure")
    testthat::expect_no_error(fn())
  }
})


# ── export_results_markdown / build_analysis_markdown ────────────────────────

# helper: build a minimal mock results object accepted by export_results_markdown
make_mock_results <- function(
  fn_name = "bench_fn",
  stage = "1-import",
  description = "a benchmark"
) {
  complexity_dt <- data.table::data.table(
    fn_name = fn_name,
    stage = stage,
    description = description,
    best_class = "O(n)",
    r_squared = 0.99,
    slope_per_n = 1e-6,
    dominant_in_stage = TRUE,
    complexity_rank = 3L,
    stage_max_rank = 3L
  )
  list(
    raw = data.table::data.table(),
    summary = data.table::data.table(),
    complexity = complexity_dt
  )
}

make_mock_results_with_runtime <- function() {
  complexity_dt <- data.table::data.table(
    fn_name = c("bench_hot", "bench_cool"),
    stage = c("1-import", "1-import"),
    description = c("hot path", "support path"),
    best_class = c("O(n^2)", "O(n)"),
    r_squared = c(0.97, 0.95),
    slope_per_n = c(2e-6, 8e-7),
    dominant_in_stage = c(TRUE, FALSE),
    complexity_rank = c(5L, 3L),
    stage_max_rank = c(5L, 5L)
  )

  summary_dt <- data.table::data.table(
    fn_name = rep(c("bench_hot", "bench_cool"), each = 3L),
    stage = rep("1-import", 6L),
    n = rep(c(100L, 1000L, 5000L), 2L),
    median_s = c(0.5, 1.0, 1.5, 0.2, 0.3, 0.5),
    mean_s = c(0.5, 1.0, 1.5, 0.2, 0.3, 0.5),
    sd_s = 0,
    min_s = c(0.5, 1.0, 1.5, 0.2, 0.3, 0.5),
    max_s = c(0.5, 1.0, 1.5, 0.2, 0.3, 0.5),
    n_reps = 1L
  )

  list(
    raw = data.table::data.table(),
    summary = summary_dt,
    complexity = complexity_dt
  )
}

testthat::test_that("export_results_markdown writes a file without error", {
  results <- make_mock_results()
  out_dir <- tempfile("perf_reports_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  testthat::expect_no_error(
    export_results_markdown(results, out_dir, preset_name = "quick")
  )

  testthat::expect_true(file.exists(file.path(
    out_dir,
    "perf_quick_whep-digitalization.md"
  )))
  testthat::expect_true(file.exists(file.path(
    out_dir,
    "perf_quick_0-general_pipeline.md"
  )))
  testthat::expect_true(file.exists(file.path(
    out_dir,
    "perf_quick_1-import_pipeline.md"
  )))
  testthat::expect_true(file.exists(file.path(
    out_dir,
    "perf_quick_2-postpro_pipeline.md"
  )))
  testthat::expect_true(file.exists(file.path(
    out_dir,
    "perf_quick_3-export_pipeline.md"
  )))
})

testthat::test_that("export_results_markdown output contains expected sections", {
  results <- make_mock_results()
  out_dir <- tempfile("perf_reports_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  export_results_markdown(results, out_dir, preset_name = "quick")
  pipeline_path <- file.path(out_dir, "perf_quick_1-import_pipeline.md")
  general_path <- file.path(out_dir, "perf_quick_whep-digitalization.md")

  raw_lines <- readLines(pipeline_path, warn = FALSE)
  raw_text <- paste(raw_lines, collapse = "\n")
  general_lines <- readLines(general_path, warn = FALSE)

  testthat::expect_true(any(grepl(
    "^# Pipeline Performance Report: perf_1-import_pipeline$",
    raw_lines
  )))
  testthat::expect_true(any(grepl("^## Stage KPI Dashboard$", raw_lines)))
  testthat::expect_true(any(grepl(
    "^## Function-Level Performance Matrix$",
    raw_lines
  )))
  testthat::expect_true(any(grepl(
    "^## Top Bottlenecks by Composite Score$",
    raw_lines
  )))
  testthat::expect_true(any(grepl(
    "^## Confidence and Uncertainty Summary$",
    raw_lines
  )))
  testthat::expect_true(any(grepl(
    "^## Optimization Priority Queue$",
    raw_lines
  )))
  testthat::expect_true(any(grepl("^## Stage Narrative$", raw_lines)))
  testthat::expect_true(any(grepl(
    "^## Runtime Share Distribution \\(ASCII\\)$",
    raw_lines
  )))
  testthat::expect_true(any(grepl("^```text$", raw_lines)))
  testthat::expect_true(grepl(
    "\\| Function\\s+\\| Description\\s+\\| Complexity\\s+\\| adj\\.R2\\s+\\| Slope per n\\s+\\| Estimated runtime \\(sample n\\)\\s+\\| Relative impact\\s+\\| Indicator\\s+\\| Bottleneck\\s+\\|",
    raw_text
  ))
  testthat::expect_false(grepl("Impact bar", raw_text, fixed = TRUE))
  testthat::expect_true(any(grepl(
    "^# General Project Performance$",
    general_lines
  )))
  testthat::expect_true(any(grepl("^## Pipeline Summary$", general_lines)))
  testthat::expect_true(any(grepl(
    "^## Cross-Stage Runtime and Risk Ranking$",
    general_lines
  )))
  testthat::expect_true(any(grepl(
    "^## Stage Bottleneck Matrix$",
    general_lines
  )))
  testthat::expect_true(any(grepl(
    "^## Global Top Bottleneck Functions$",
    general_lines
  )))
  testthat::expect_true(any(grepl(
    "^## Recommended Optimization Roadmap$",
    general_lines
  )))
})

testthat::test_that("export_results_markdown preserves strings with tab/newline control chars", {
  results <- make_mock_results(description = "line1\nline2\ttabbed")
  out_dir <- tempfile("perf_reports_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  testthat::expect_no_error(
    export_results_markdown(results, out_dir, preset_name = "quick")
  )

  raw_text <- paste(
    readLines(
      file.path(out_dir, "perf_quick_1-import_pipeline.md"),
      warn = FALSE
    ),
    collapse = "\n"
  )
  testthat::expect_true(grepl("line1", raw_text, fixed = TRUE))
  testthat::expect_true(grepl("line2", raw_text, fixed = TRUE))
  testthat::expect_true(grepl("tabbed", raw_text, fixed = TRUE))
})

testthat::test_that("export_results_markdown writes preset metadata lines", {
  results <- make_mock_results()
  out_dir <- tempfile("perf_reports_")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  export_results_markdown(results, out_dir, preset_name = "quick")

  pipeline_lines <- readLines(
    file.path(out_dir, "perf_quick_1-import_pipeline.md"),
    warn = FALSE
  )
  general_lines <- readLines(
    file.path(out_dir, "perf_quick_whep-digitalization.md"),
    warn = FALSE
  )

  testthat::expect_true(any(grepl("^- Preset: quick$", pipeline_lines)))
  testthat::expect_true(any(grepl("^- Preset: quick$", general_lines)))
})

testthat::test_that("build_analysis_markdown handles NA r_squared", {
  results <- make_mock_results()
  results$complexity[, r_squared := NA_real_]
  lines <- build_analysis_markdown(results)
  testthat::expect_true(any(grepl("N/A", lines, fixed = TRUE)))
})

testthat::test_that("prepare_reporting_metrics computes stage and function impact metrics", {
  results <- make_mock_results_with_runtime()
  metrics <- prepare_reporting_metrics(results)

  testthat::expect_true(data.table::is.data.table(metrics$stage_summary))
  testthat::expect_equal(metrics$stage_summary$function_count[[1L]], 2L)
  testthat::expect_equal(
    metrics$stage_summary$expensive_function_count[[1L]],
    1L
  )
  testthat::expect_equal(
    round(metrics$stage_summary$expensive_function_pct[[1L]], 1),
    50.0
  )

  hot_impact <- metrics$function_metrics[
    fn_name == "bench_hot",
    relative_impact
  ][[1L]]
  testthat::expect_equal(round(hot_impact, 2), 0.75)
  testthat::expect_true(all(c(100L, 1000L, 5000L) %in% metrics$sample_n_values))

  testthat::expect_true(all(
    c(
      "bottleneck_score",
      "confidence_label",
      "high_complexity_flag",
      "high_impact_flag",
      "low_confidence_flag",
      "high_volatility_flag",
      "critical_bottleneck_flag",
      "diagnostic_flags",
      "slowdown_drivers",
      "priority_tier"
    ) %in%
      names(metrics$function_metrics)
  ))

  testthat::expect_true("stage_risk_score" %in% names(metrics$stage_summary))
  testthat::expect_true(data.table::is.data.table(metrics$stage_priority_queue))
  testthat::expect_true(data.table::is.data.table(metrics$global_bottlenecks))
  testthat::expect_true(data.table::is.data.table(
    metrics$stage_bottleneck_matrix
  ))
  testthat::expect_true(nrow(metrics$stage_priority_queue) >= 1L)
  testthat::expect_true(nrow(metrics$global_bottlenecks) >= 1L)
})

testthat::test_that("build_analysis_markdown includes chart-ready and projection sections", {
  results <- make_mock_results_with_runtime()
  lines <- build_analysis_markdown(results)
  raw_text <- paste(lines, collapse = "\n")

  testthat::expect_true(any(grepl(
    "^## Chart Data: Function Complexities$",
    lines
  )))
  testthat::expect_true(any(grepl(
    "^## Chart Data: Stage Runtime Proportions$",
    lines
  )))
  testthat::expect_true(any(grepl(
    "^## Chart Data: Slope per n and Relative Impact$",
    lines
  )))
  testthat::expect_true(any(grepl(
    "^## Runtime Projections by Sample n$",
    lines
  )))
  testthat::expect_true(grepl("75.0%", raw_text, fixed = TRUE))
  testthat::expect_true(grepl("!!! (critical)", raw_text, fixed = TRUE))
})

testthat::test_that("time_fn suppresses bench GC filtering warning noise", {
  captured_warnings <- character(0L)

  withCallingHandlers(
    time_fn(function() {
      x <- rnorm(10000L)
      sum(x)
    }),
    warning = function(w) {
      captured_warnings <<- c(captured_warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  has_gc_filter_warning <- any(grepl(
    "GC in every iteration; so filtering is disabled",
    captured_warnings,
    fixed = TRUE
  ))

  testthat::expect_false(has_gc_filter_warning)
})

# ── run_benchmark (progressor integration) ───────────────────────────────────

testthat::test_that("run_benchmark accepts a progressor and calls it once per input size", {
  sizes <- c(100L, 200L, 300L)
  n_calls <- 0L

  # a mock progressor that simply counts calls
  mock_progressor <- function(msg = NULL) {
    n_calls <<- n_calls + 1L
  }

  fn_factory <- function(n) function() Sys.sleep(0)

  result <- run_benchmark(
    fn_factory,
    sizes,
    n_reps = 1L,
    quiet = TRUE,
    progressor = mock_progressor
  )

  testthat::expect_equal(n_calls, length(sizes))
})

testthat::test_that("run_benchmark progressor message contains n and fraction", {
  sizes <- c(100L, 500L)
  messages <- character(0L)

  mock_progressor <- function(msg = NULL) {
    if (!is.null(msg)) messages <<- c(messages, msg)
  }

  fn_factory <- function(n) function() Sys.sleep(0)

  run_benchmark(
    fn_factory,
    sizes,
    n_reps = 1L,
    quiet = TRUE,
    progressor = mock_progressor
  )

  # each message should mention the size and the i/T fraction
  testthat::expect_true(any(grepl("100", messages)))
  testthat::expect_true(any(grepl("500", messages)))
  testthat::expect_true(any(grepl("1/2", messages)))
  testthat::expect_true(any(grepl("2/2", messages)))
})

testthat::test_that("run_benchmark with quiet=TRUE and no progressor emits no messages", {
  fn_factory <- function(n) function() Sys.sleep(0)
  sizes <- c(50L, 100L)

  msgs <- character(0L)
  withCallingHandlers(
    run_benchmark(
      fn_factory,
      sizes,
      n_reps = 1L,
      quiet = TRUE,
      progressor = NULL
    ),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )

  testthat::expect_length(msgs, 0L)
})

testthat::test_that("run_benchmark returns correct data.table structure when progressor is used", {
  sizes <- c(100L, 200L)
  mock_progressor <- function(msg = NULL) invisible(NULL)
  fn_factory <- function(n) function() Sys.sleep(0)

  result <- run_benchmark(
    fn_factory,
    sizes,
    n_reps = 2L,
    quiet = TRUE,
    progressor = mock_progressor
  )

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_true(all(c("n", "rep", "elapsed_s") %in% names(result)))
  testthat::expect_equal(nrow(result), length(sizes) * 2L)
})
