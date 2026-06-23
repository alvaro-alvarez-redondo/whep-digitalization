# tests/3-export_pipeline/test-export-lists.R
# unit tests for R/3-export_pipeline/31-lists/*.R

source(here::here("tests", "test_helper.R"), echo = FALSE)
export_scripts <- c(
  "30-processed_data/01-build-processed-export-path.R",
  "30-processed_data/02-collect-layer-tables.R",
  "30-processed_data/03-write-processed-table-fast.R",
  "30-processed_data/04-export-processed-data.R",
  "31-lists/01-sheet-order-and-infer.R",
  "31-lists/02-build-path-and-unique-values.R",
  "31-lists/03-resolve-and-compare.R",
  "31-lists/04-cache-and-write.R"
)

lapply(export_scripts, function(script_name) {
  source(here::here("r", "3-export_pipeline", script_name), echo = FALSE)
})


# --- get_lists_sheet_order ---------------------------------------------------

testthat::test_that("get_lists_sheet_order returns fixed order", {
  result <- get_lists_sheet_order()

  testthat::expect_identical(
    result,
    c("raw", "clean", "normalize", "harmonize")
  )
})


# --- build_layer_tables_by_sheet ---------------------------------------------

testthat::test_that("build_layer_tables_by_sheet enforces fixed sheet keys", {
  layer_tables <- list(
    whep_data_raw = data.frame(polity = c("a", "b")),
    whep_data_harmonize = data.frame(polity = c("a", "c"))
  )

  result <- build_layer_tables_by_sheet(layer_tables)

  testthat::expect_identical(
    names(result),
    c("raw", "clean", "normalize", "harmonize")
  )
  testthat::expect_true(nrow(result$clean) == 0)
  testthat::expect_true(nrow(result$normalize) == 0)
})

testthat::test_that("build_layer_tables_by_sheet handles empty layer list", {
  result <- build_layer_tables_by_sheet(list())

  testthat::expect_identical(
    names(result),
    c("raw", "clean", "normalize", "harmonize")
  )
  testthat::expect_true(all(vapply(result, nrow, integer(1)) == 0L))
})


# --- collect_union_columns ---------------------------------------------------

testthat::test_that("collect_union_columns returns sorted unique union", {
  layer_by_sheet <- list(
    raw = data.table::data.table(polity = c("a"), year = c("2020")),
    clean = data.table::data.table(polity = c("a")),
    normalize = data.table::data.table(polity = c("a")),
    harmonize = data.table::data.table(polity = c("a"), value = c("1"))
  )

  result <- collect_union_columns(layer_by_sheet)

  testthat::expect_identical(result, sort(c("polity", "year", "value")))
})

testthat::test_that("collect_union_columns handles empty tables", {
  layer_by_sheet <- list(
    raw = data.table::data.table(),
    clean = data.table::data.table(),
    normalize = data.table::data.table(),
    harmonize = data.table::data.table()
  )

  result <- collect_union_columns(layer_by_sheet)

  testthat::expect_equal(length(result), 0L)
})


# --- build_column_unique_cache -----------------------------------------------

testthat::test_that("compute_unique_column_values prepends (blank) when NA exists", {
  input_dt <- data.table::data.table(
    polity = c("a", NA_character_, "b", NA_character_)
  )

  result <- compute_unique_column_values(input_dt, "polity")

  testthat::expect_identical(result, c("(blank)", "a", "b"))
})

testthat::test_that("compute_unique_column_values keeps numeric sort with blank first", {
  input_dt <- data.table::data.table(value = c(10, NA_real_, 2, 1, NA_real_))

  result <- compute_unique_column_values(input_dt, "value")

  testthat::expect_identical(result, c("(blank)", "1", "2", "10"))
})

testthat::test_that("build_column_unique_cache returns empty vectors for missing columns", {
  layer_by_sheet <- list(
    raw = data.table::data.table(polity = c("a", "b")),
    clean = data.table::data.table(),
    normalize = data.table::data.table(polity = c("a", "b")),
    harmonize = data.table::data.table(polity = c("a", "c"))
  )

  union_columns <- collect_union_columns(layer_by_sheet)
  cache <- build_column_unique_cache(layer_by_sheet, union_columns)

  testthat::expect_true(length(cache$clean$polity) == 0)
  testthat::expect_setequal(cache$raw$polity, c("a", "b"))
  testthat::expect_setequal(cache$harmonize$polity, c("a", "c"))
})


# --- normalize_for_comparison ------------------------------------------------

testthat::test_that("normalize_for_comparison drops year column", {
  input_dt <- data.table::data.table(
    year = c("2020", "2021"),
    value = c("x", "y")
  )

  result <- normalize_for_comparison(input_dt)

  testthat::expect_false("year" %in% names(result))
  testthat::expect_true("value" %in% names(result))
})

testthat::test_that("normalize_for_comparison sorts rows and columns", {
  input_dt <- data.table::data.table(
    b = c("2", "1"),
    a = c("y", "x")
  )

  result <- normalize_for_comparison(input_dt)

  testthat::expect_identical(names(result), c("a", "b"))
  testthat::expect_equal(result$a, c("x", "y"))
})


# --- are_list_tables_identical -----------------------------------------------

testthat::test_that("clean/harmonize comparison ignores row and column order", {
  clean_dt <- data.table::data.table(
    value = c("x", "y", "z"),
    code = c("1", "2", "3")
  )
  harmonize_dt <- data.table::data.table(
    code = c("3", "1", "2"),
    value = c("z", "x", "y")
  )

  result <- are_list_tables_identical(clean_dt, harmonize_dt)

  testthat::expect_true(result)
})

testthat::test_that("are_list_tables_identical detects different values", {
  dt1 <- data.table::data.table(value = c("x", "y"))
  dt2 <- data.table::data.table(value = c("x", "z"))

  result <- are_list_tables_identical(dt1, dt2)

  testthat::expect_false(result)
})


# --- resolve_list_sheet_payloads ---------------------------------------------

testthat::test_that("all-equal layers produce single combined sheet", {
  dt <- data.table::data.table(value = c("a", "b"))

  result <- resolve_list_sheet_payloads(dt, dt, dt, dt)

  testthat::expect_identical(names(result), "raw_clean_normalize_harmonize")
})

testthat::test_that("raw different, clean=normalize=harmonize produce raw + clean_normalize_harmonize", {
  raw <- data.table::data.table(value = c("a"))
  clean <- data.table::data.table(value = c("b"))
  normalize <- data.table::data.table(value = c("b"))
  harmonize <- data.table::data.table(value = c("b"))

  result <- resolve_list_sheet_payloads(raw, clean, normalize, harmonize)

  testthat::expect_setequal(
    names(result),
    c("raw", "clean_normalize_harmonize")
  )
})

testthat::test_that("normalize=harmonize and others different produce merged normalize_harmonize", {
  raw <- data.table::data.table(value = c("a"))
  clean <- data.table::data.table(value = c("b"))
  normalize <- data.table::data.table(value = c("c"))
  harmonize <- data.table::data.table(value = c("c"))

  result <- resolve_list_sheet_payloads(raw, clean, normalize, harmonize)

  testthat::expect_setequal(
    names(result),
    c("raw", "clean", "normalize_harmonize")
  )
})

testthat::test_that("all different produce raw + clean + normalize + harmonize", {
  raw <- data.table::data.table(value = c("a"))
  clean <- data.table::data.table(value = c("b"))
  normalize <- data.table::data.table(value = c("c"))
  harmonize <- data.table::data.table(value = c("d"))

  result <- resolve_list_sheet_payloads(raw, clean, normalize, harmonize)

  testthat::expect_setequal(
    names(result),
    c("raw", "clean", "normalize", "harmonize")
  )
})


# --- write_column_lists_workbook ---------------------------------------------

testthat::test_that("write_column_lists_workbook writes all-equal as raw_clean_normalize_harmonize", {
  config <- build_test_config()

  unique_cache <- list(
    raw = list(polity = c("a", "b")),
    clean = list(polity = c("a", "b")),
    normalize = list(polity = c("a", "b")),
    harmonize = list(polity = c("a", "b"))
  )

  path <- write_column_lists_workbook(
    column_name = "polity",
    unique_cache = unique_cache,
    config = config,
    overwrite = TRUE
  )

  sheets <- readxl::excel_sheets(path)
  testthat::expect_setequal(sheets, "raw_clean_normalize_harmonize")
})

testthat::test_that("write_column_lists_workbook writes raw + clean_normalize_harmonize", {
  config <- build_test_config()

  unique_cache <- list(
    raw = list(polity = c("a", "b")),
    clean = list(polity = c("c", "d")),
    normalize = list(polity = c("c", "d")),
    harmonize = list(polity = c("c", "d"))
  )

  path <- write_column_lists_workbook(
    column_name = "polity",
    unique_cache = unique_cache,
    config = config,
    overwrite = TRUE
  )

  sheets <- readxl::excel_sheets(path)
  testthat::expect_setequal(sheets, c("raw", "clean_normalize_harmonize"))
})

testthat::test_that("write_column_lists_workbook merges normalize_harmonize when those two match", {
  config <- build_test_config()

  unique_cache <- list(
    raw = list(polity = c("a", "b")),
    clean = list(polity = c("c", "d")),
    normalize = list(polity = c("e", "f")),
    harmonize = list(polity = c("e", "f"))
  )

  path <- write_column_lists_workbook(
    column_name = "polity",
    unique_cache = unique_cache,
    config = config,
    overwrite = TRUE
  )

  sheets <- readxl::excel_sheets(path)
  testthat::expect_setequal(sheets, c("raw", "clean", "normalize_harmonize"))
})

testthat::test_that("write_column_lists_workbook writes raw + clean + normalize + harmonize", {
  config <- build_test_config()

  unique_cache <- list(
    raw = list(polity = c("a", "b")),
    clean = list(polity = c("c", "d")),
    normalize = list(polity = c("e", "f")),
    harmonize = list(polity = c("g", "h"))
  )

  path <- write_column_lists_workbook(
    column_name = "polity",
    unique_cache = unique_cache,
    config = config,
    overwrite = TRUE
  )

  sheets <- readxl::excel_sheets(path)
  testthat::expect_setequal(sheets, c("raw", "clean", "normalize", "harmonize"))
})


# --- export_lists ------------------------------------------------------------

testthat::test_that("export_lists honors configured lists_to_export columns", {
  config <- build_test_config()

  data_objects <- list(
    demo_raw = data.table::data.table(
      polity = c("a", "b"),
      document = c("doc_a.xlsx", "doc_b.xlsx"),
      value = c("1", "2"),
      year = c("2020", "2021")
    ),
    demo_clean = data.table::data.table(
      polity = c("a", "b"),
      document = c("doc_a.xlsx", "doc_b.xlsx"),
      value = c("1", "2"),
      year = c("2020", "2021")
    ),
    demo_normalize = data.table::data.table(
      polity = c("a", "b"),
      document = c("doc_a.xlsx", "doc_b.xlsx"),
      value = c("1", "2"),
      year = c("2020", "2021")
    ),
    demo_harmonize = data.table::data.table(
      polity = c("a", "b"),
      document = c("doc_a.xlsx", "doc_b.xlsx"),
      value = c("1", "2"),
      year = c("2020", "2021")
    )
  )

  output_paths <- export_lists(
    config = config,
    data_objects = data_objects,
    overwrite = TRUE,
    env = new.env(parent = emptyenv())
  )

  testthat::expect_true("polity" %in% names(output_paths))
  testthat::expect_false("document" %in% names(output_paths))
  testthat::expect_false("value" %in% names(output_paths))
  testthat::expect_false("year" %in% names(output_paths))
})

testthat::test_that("export_lists includes document only when explicitly configured", {
  config <- build_test_config()
  config$export_config$lists_to_export <- c("polity", "document")

  data_objects <- list(
    demo_raw = data.table::data.table(
      polity = c("a", "b"),
      document = c("doc_a.xlsx", "doc_b.xlsx")
    ),
    demo_clean = data.table::data.table(
      polity = c("a", "b"),
      document = c("doc_a.xlsx", "doc_b.xlsx")
    ),
    demo_normalize = data.table::data.table(
      polity = c("a", "b"),
      document = c("doc_a.xlsx", "doc_b.xlsx")
    ),
    demo_harmonize = data.table::data.table(
      polity = c("a", "b"),
      document = c("doc_a.xlsx", "doc_b.xlsx")
    )
  )

  output_paths <- export_lists(
    config = config,
    data_objects = data_objects,
    overwrite = TRUE,
    env = new.env(parent = emptyenv())
  )

  testthat::expect_true("polity" %in% names(output_paths))
  testthat::expect_true("document" %in% names(output_paths))
})


# --- bug-fix regressions: determinism, union, filename collisions -----------

testthat::test_that("compute_unique_column_values sorts in locale-independent radix order", {
  input_dt <- data.table::data.table(
    commodity = c("Zebra", "apple", "Banana", "apple")
  )

  result <- compute_unique_column_values(input_dt, "commodity")

  # radix (C-locale) order: uppercase before lowercase, identical across locales
  testthat::expect_identical(result, c("Banana", "Zebra", "apple"))
})

testthat::test_that("build_layer_tables_by_sheet unions multiple objects mapping to one sheet", {
  layer_tables <- list(
    alpha_raw = data.table::data.table(polity = c("a", "b")),
    beta_raw = data.table::data.table(polity = c("c"))
  )

  result <- build_layer_tables_by_sheet(layer_tables)

  testthat::expect_setequal(result$raw$polity, c("a", "b", "c"))
  testthat::expect_equal(nrow(result$raw), 3L)
})

testthat::test_that("export_lists aborts when configured columns collide on filename", {
  config <- build_test_config()
  config$export_config$lists_to_export <- c("polity", "Polity")

  data_objects <- list(
    demo_raw = data.table::data.table(polity = c("a"), Polity = c("a")),
    demo_clean = data.table::data.table(polity = c("a"), Polity = c("a")),
    demo_normalize = data.table::data.table(polity = c("a"), Polity = c("a")),
    demo_harmonize = data.table::data.table(polity = c("a"), Polity = c("a"))
  )

  testthat::expect_error(
    export_lists(
      config = config,
      data_objects = data_objects,
      overwrite = TRUE,
      env = new.env(parent = emptyenv())
    ),
    "same\\s+workbook\\s+filename"
  )
})
