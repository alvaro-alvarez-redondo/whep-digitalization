options(
  whep.run_export_pipeline.auto = FALSE
)

source(here::here("r", "0-general_pipeline", "02-helpers", "02-assertions.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-time-formatting.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-string-normalization.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-numeric-coercion.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-token-extraction.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-data-table.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-export-validation.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-config-accessors.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-progress.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-sorting.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-environment.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-checkpoints.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-data-cleaning.R"), echo = FALSE)
source(here::here("r", "0-general_pipeline", "02-helpers", "02-io-cache.R"), echo = FALSE)
source(
  here::here("r", "3-export_pipeline", "30-export_data.R"),
  echo = FALSE
)
source(
  here::here("r", "3-export_pipeline", "31-export_lists.R"),
  echo = FALSE
)

testthat::test_that("collect_union_columns returns deterministic union", {
  layer_by_sheet <- list(
    raw = data.table::data.table(
      country = c("a", "b"),
      year = c("2020", "2021")
    ),
    clean = data.table::data.table(country = c("a", "c")),
    normalize = data.table::data.table(unit = c("kg", "t")),
    harmonize = data.table::data.table(country = c("a"), value = c("1"))
  )

  union_columns <- collect_union_columns(layer_by_sheet)

  testthat::expect_identical(
    union_columns,
    sort(c("country", "year", "unit", "value"))
  )
})

testthat::test_that("build_column_unique_cache returns empty vectors for missing columns", {
  layer_by_sheet <- list(
    raw = data.table::data.table(country = c("a", "b")),
    clean = data.table::data.table(),
    normalize = data.table::data.table(),
    harmonize = data.table::data.table(country = c("a", "c"))
  )

  union_columns <- collect_union_columns(layer_by_sheet)
  cache <- build_column_unique_cache(layer_by_sheet, union_columns)

  testthat::expect_true(length(cache$clean$country) == 0)
  testthat::expect_setequal(cache$raw$country, c("a", "b"))
})

testthat::test_that("export_lists excludes normalize standalone sheet and value/year workbooks", {
  lists_dir <- tempfile("lists-export-")

  config <- list(
    paths = list(
      data = list(
        export = list(
          lists = lists_dir
        )
      )
    ),
    export_config = list(
      lists_to_export = c("country")
    )
  )

  data_objects <- list(
    demo_raw = data.table::data.table(
      country = c("a", "b"),
      value = c("1", "2"),
      year = c("2020", "2021")
    ),
    demo_clean = data.table::data.table(
      country = c("a", "b"),
      value = c("1", "2"),
      year = c("2020", "2021")
    ),
    demo_normalize = data.table::data.table(
      country = c("a", "b"),
      value = c("1", "2"),
      year = c("2020", "2021")
    ),
    demo_harmonize = data.table::data.table(
      country = c("a", "b"),
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

  testthat::expect_true("country" %in% names(output_paths))
  testthat::expect_false("value" %in% names(output_paths))
  testthat::expect_false("year" %in% names(output_paths))

  workbook_sheets <- readxl::excel_sheets(output_paths[["country"]])
  testthat::expect_false("normalize" %in% workbook_sheets)
})

testthat::test_that("write_column_lists_workbook writes raw_clean_normalize_harmonize for all-equal tables", {
  lists_dir <- tempfile("lists-equal-")

  config <- list(
    paths = list(
      data = list(
        export = list(
          lists = lists_dir
        )
      )
    )
  )

  unique_cache <- list(
    raw = list(country = c("a", "b")),
    clean = list(country = c("a", "b")),
    normalize = list(country = c("a", "b")),
    harmonize = list(country = c("a", "b"))
  )

  workbook_path <- write_column_lists_workbook(
    column_name = "country",
    unique_cache = unique_cache,
    config = config,
    overwrite = TRUE
  )

  workbook_sheets <- readxl::excel_sheets(workbook_path)

  testthat::expect_setequal(workbook_sheets, c("raw_clean_normalize_harmonize"))
  testthat::expect_false("raw" %in% workbook_sheets)
  testthat::expect_false("clean" %in% workbook_sheets)
  testthat::expect_false("normalize" %in% workbook_sheets)
  testthat::expect_false("harmonize" %in% workbook_sheets)
  testthat::expect_false("clean_normalize_harmonize" %in% workbook_sheets)
})

testthat::test_that("write_column_lists_workbook writes raw + clean_normalize_harmonize when clean/normalize/harmonize equal", {
  lists_dir <- tempfile("lists-different-")

  config <- list(
    paths = list(
      data = list(
        export = list(
          lists = lists_dir
        )
      )
    )
  )

  unique_cache <- list(
    raw = list(country = c("a", "b")),
    clean = list(country = c("c", "d")),
    normalize = list(country = c("c", "d")),
    harmonize = list(country = c("c", "d"))
  )

  workbook_path <- write_column_lists_workbook(
    column_name = "country",
    unique_cache = unique_cache,
    config = config,
    overwrite = TRUE
  )

  workbook_sheets <- readxl::excel_sheets(workbook_path)

  testthat::expect_setequal(workbook_sheets, c("raw", "clean_normalize_harmonize"))
  testthat::expect_false("clean" %in% workbook_sheets)
  testthat::expect_false("normalize" %in% workbook_sheets)
  testthat::expect_false("harmonize" %in% workbook_sheets)
})

testthat::test_that("write_column_lists_workbook writes raw, clean, normalize, harmonize when all differ", {
  lists_dir <- tempfile("lists-all-different-")

  config <- list(
    paths = list(
      data = list(
        export = list(
          lists = lists_dir
        )
      )
    )
  )

  unique_cache <- list(
    raw = list(country = c("a", "b")),
    clean = list(country = c("c", "d")),
    normalize = list(country = c("e", "f")),
    harmonize = list(country = c("g", "h"))
  )

  workbook_path <- write_column_lists_workbook(
    column_name = "country",
    unique_cache = unique_cache,
    config = config,
    overwrite = TRUE
  )

  workbook_sheets <- readxl::excel_sheets(workbook_path)

  testthat::expect_setequal(
    workbook_sheets,
    c("raw", "clean", "normalize", "harmonize")
  )
  testthat::expect_false("raw_clean_normalize_harmonize" %in% workbook_sheets)
})

testthat::test_that("clean/harmonize comparison ignores row and column order differences", {
  clean_dt <- data.table::data.table(
    value = c("x", "y", "z"),
    code = c("1", "2", "3")
  )
  harmonize_dt <- data.table::data.table(
    code = c("3", "1", "2"),
    value = c("z", "x", "y")
  )

  is_identical <- are_list_tables_identical(
    left_dt = clean_dt,
    right_dt = harmonize_dt
  )

  testthat::expect_true(is_identical)
})

testthat::test_that("normalize_for_comparison drops year column", {
  input_dt <- data.table::data.table(
    year = c("2020", "2021"),
    value = c("x", "y")
  )

  normalize_dt <- normalize_for_comparison(input_dt)

  testthat::expect_false("year" %in% names(normalize_dt))
  testthat::expect_true("value" %in% names(normalize_dt))
  testthat::expect_true("year" %in% names(input_dt))
  testthat::expect_identical(input_dt$year, c("2020", "2021"))
})

testthat::test_that("are_list_tables_identical returns FALSE for row-count mismatch", {
  left_dt <- data.table::data.table(value = c("a", "b"))
  right_dt <- data.table::data.table(value = c("a"))

  result <- are_list_tables_identical(left_dt, right_dt)

  testthat::expect_false(result)
})
