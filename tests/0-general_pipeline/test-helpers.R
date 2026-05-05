# tests/0-general_pipeline/test-helpers.R
# unit tests for R/0-general_pipeline/02-helpers/ modules

source(here::here("tests", "test_helper.R"), echo = FALSE)


# --- normalize_string_impl ---------------------------------------------------

testthat::test_that("normalize_string_impl converts to lowercase ascii", {
  testthat::expect_identical(
    normalize_string_impl("Hello World"),
    "hello world"
  )
  testthat::expect_identical(normalize_string_impl("UPPER"), "upper")
})

testthat::test_that("normalize_string_impl removes non-alphanumeric characters", {
  testthat::expect_identical(normalize_string_impl("a-b_c!d"), "a b c d")
  testthat::expect_identical(normalize_string_impl("test@#$123"), "test 123")
})

testthat::test_that("normalize_string_impl squishes whitespace", {
  testthat::expect_identical(normalize_string_impl("a   b  c"), "a b c")
  testthat::expect_identical(normalize_string_impl("  leading  "), "leading")
})

testthat::test_that("normalize_string_impl handles accented characters", {
  result <- normalize_string_impl("café résumé")
  testthat::expect_true(grepl("^[a-z0-9 ]+$", result))
})

testthat::test_that("normalize_string_impl preserves NA values", {
  result <- normalize_string_impl(c("hello", NA_character_))
  testthat::expect_true(is.na(result[2]))
})

testthat::test_that("normalize_string_impl matches normalize_string output", {
  test_inputs <- c(
    "Hello World",
    "café résumé",
    "a-b_c!d",
    "  leading  ",
    "UPPER",
    "test@#$123",
    "a   b  c"
  )
  testthat::expect_identical(
    normalize_string_impl(test_inputs),
    normalize_string(test_inputs)
  )
})

testthat::test_that("normalize_string_impl handles high-duplication inputs", {
  duplicated_values <- rep(c("Café", "RICE-01", "North  America"), 200L)
  result <- normalize_string_impl(duplicated_values)

  testthat::expect_identical(
    result,
    normalize_string(duplicated_values)
  )
})


# --- normalize_string --------------------------------------------------------

testthat::test_that("normalize_string converts to lowercase ascii", {
  testthat::expect_identical(normalize_string("Hello World"), "hello world")
  testthat::expect_identical(normalize_string("UPPER"), "upper")
})

testthat::test_that("normalize_string removes non-alphanumeric characters", {
  testthat::expect_identical(normalize_string("a-b_c!d"), "a b c d")
  testthat::expect_identical(normalize_string("test@#$123"), "test 123")
})

testthat::test_that("normalize_string squishes whitespace", {
  testthat::expect_identical(normalize_string("a   b  c"), "a b c")
  testthat::expect_identical(normalize_string("  leading  "), "leading")
})

testthat::test_that("normalize_string handles accented characters", {
  result <- normalize_string("café résumé")
  testthat::expect_true(grepl("^[a-z0-9 ]+$", result))
})

testthat::test_that("normalize_string preserves NA values", {
  result <- normalize_string(c("hello", NA_character_))
  testthat::expect_true(is.na(result[2]))
})


# --- clean_footnote ----------------------------------------------------------

testthat::test_that("clean_footnote converts to lowercase ascii", {
  testthat::expect_identical(clean_footnote("Note A"), "note a")
  testthat::expect_identical(clean_footnote("UPPER CASE"), "upper case")
})

testthat::test_that("clean_footnote handles accented characters", {
  result <- clean_footnote("données révisées")

  allowed_chars <- c(
    letters,
    as.character(0:9),
    " ",
    ";",
    "/",
    "*",
    "(",
    ")",
    ".",
    ",",
    "-",
    "#",
    "%",
    ":"
  )
  result_chars <- strsplit(result, "", fixed = TRUE)[[1]]

  testthat::expect_true(all(result_chars %in% allowed_chars))
})

testthat::test_that("clean_footnote preserves footnote-safe special characters", {
  input <- "note 1/ official data (revised); 50% estimate #2 * marker"
  result <- clean_footnote(input)
  testthat::expect_true(grepl(";", result, fixed = TRUE))
  testthat::expect_true(grepl("/", result, fixed = TRUE))
  testthat::expect_true(grepl("(", result, fixed = TRUE))
  testthat::expect_true(grepl(")", result, fixed = TRUE))
  testthat::expect_true(grepl("%", result, fixed = TRUE))
  testthat::expect_true(grepl("#", result, fixed = TRUE))
  testthat::expect_true(grepl("*", result, fixed = TRUE))
})

testthat::test_that("clean_footnote removes characters not in footnotes", {
  result <- clean_footnote("note! @value")
  testthat::expect_false(grepl("!", result, fixed = TRUE))
  testthat::expect_false(grepl("@", result, fixed = TRUE))
})

testthat::test_that("clean_footnote squishes and trims whitespace", {
  testthat::expect_identical(clean_footnote("  note  "), "note")
})

testthat::test_that("clean_footnote preserves NA values", {
  result <- clean_footnote(c("note", NA_character_))
  testthat::expect_true(is.na(result[2]))
})

testthat::test_that("clean_footnote differs from normalize_string on special chars", {
  input <- "note 1/ data; (revised)"
  fn_result <- clean_footnote(input)
  ns_result <- normalize_string(input)
  # normalize_string strips /, ;, (, ) but clean_footnote keeps them
  testthat::expect_true(grepl(";", fn_result, fixed = TRUE))
  testthat::expect_false(grepl(";", ns_result, fixed = TRUE))
})


# --- normalize_filename ------------------------------------------------------

testthat::test_that("normalize_filename replaces spaces with underscores", {
  testthat::expect_identical(
    normalize_filename("food balance sheet"),
    "food_balance_sheet"
  )
})

testthat::test_that("normalize_filename replaces empty/NA with unknown", {
  testthat::expect_identical(normalize_filename(""), "unknown")
  testthat::expect_identical(normalize_filename(NA_character_), "unknown")
})


# --- coerce_numeric_safe ----------------------------------------------------

testthat::test_that("coerce_numeric_safe converts numeric strings correctly", {
  result <- coerce_numeric_safe(c("1", " 2.5 ", "3"))
  testthat::expect_equal(result, c(1, 2.5, 3))
})

testthat::test_that("coerce_numeric_safe handles empty and NA values", {
  result <- coerce_numeric_safe(c("", NA_character_, "4"))
  testthat::expect_true(is.na(result[1]))
  testthat::expect_true(is.na(result[2]))
  testthat::expect_equal(result[3], 4)
})

testthat::test_that("coerce_numeric_safe returns NA for non-numeric", {
  result <- coerce_numeric_safe(c("abc", "1"))
  testthat::expect_true(is.na(result[1]))
  testthat::expect_equal(result[2], 1)
})

testthat::test_that("coerce_numeric_safe preserves numeric vectors", {
  x <- c(1, 2.5, NA_real_, -3)
  testthat::expect_identical(coerce_numeric_safe(x), x)
})

testthat::test_that("coerce_numeric_safe parses numeric factors correctly", {
  x <- factor(c("1", "2.5", "", NA_character_))
  result <- coerce_numeric_safe(x)

  testthat::expect_equal(result[1], 1)
  testthat::expect_equal(result[2], 2.5)
  testthat::expect_true(is.na(result[3]))
  testthat::expect_true(is.na(result[4]))
})


# --- extract_yearbook --------------------------------------------------------

testthat::test_that("extract_yearbook returns combined tokens", {
  parts <- c("whep", "yb", "2020", "2021", "file.xlsx")
  result <- extract_yearbook(parts)

  testthat::expect_identical(result, "yb_2020")
})

testthat::test_that("extract_yearbook returns NA for short input", {
  parts <- c("whep", "yb")
  result <- extract_yearbook(parts)

  testthat::expect_true(is.na(result))
})

testthat::test_that("extract_yearbook uses first 4-digit token", {
  parts <- c("r", "iia", "crops", "trade", "1909", "134", "file.xlsx")
  result <- extract_yearbook(parts)

  testthat::expect_identical(result, "iia_1909")
})


# --- extract_commodity ---------------------------------------------------------

testthat::test_that("extract_commodity extracts tokens from position 7 onward", {
  parts <- c("a", "b", "c", "d", "e", "f", "rice", "grain.xlsx")
  result <- extract_commodity(parts)

  testthat::expect_identical(result, "rice_grain")
})

testthat::test_that("extract_commodity returns NA for short input", {
  parts <- c("a", "b", "c")
  result <- extract_commodity(parts)

  testthat::expect_true(is.na(result))
})


# --- ensure_data_table -------------------------------------------------------

testthat::test_that("ensure_data_table converts data.frame to data.table", {
  df <- data.frame(a = 1:3)
  result <- ensure_data_table(df)

  testthat::expect_true(data.table::is.data.table(result))
})

testthat::test_that("ensure_data_table preserves existing data.table", {
  dt <- data.table::data.table(a = 1:3)
  result <- ensure_data_table(dt)

  testthat::expect_true(data.table::is.data.table(result))
})

testthat::test_that("ensure_data_table converts in place via setDT", {
  df <- data.frame(a = 1:3, b = c("x", "y", "z"))
  result <- ensure_data_table(df)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_identical(result$a, 1:3)
  testthat::expect_identical(result$b, c("x", "y", "z"))
})

testthat::test_that("ensure_data_table returns identity for data.table input", {
  dt <- data.table::data.table(a = 1:3)
  result <- ensure_data_table(dt)

  testthat::expect_identical(
    data.table::address(result),
    data.table::address(dt)
  )
})


# --- sort_pipeline_stage_dt --------------------------------------------------

testthat::test_that("sort_pipeline_stage_dt sorts by canonical stage columns", {
  dt <- data.table::data.table(
    hemisphere = c("north", "north", "south"),
    continent = c("asia", "asia", "africa"),
    country = c("japan", "china", "kenya"),
    commodity = c("rice", "rice", "tea"),
    variable = c("yield", "yield", "yield"),
    unit = c("kg", "kg", "kg"),
    year = c("2021", "2020", "2022"),
    notes = c("b", "a", "a")
  )

  result <- sort_pipeline_stage_dt(dt)

  testthat::expect_identical(result$country, c("kenya", "china", "japan"))
  testthat::expect_identical(result$year, c("2022", "2020", "2021"))
  testthat::expect_identical(result$notes, c("a", "a", "b"))
})

testthat::test_that("sort_pipeline_stage_dt ignores missing sort columns", {
  dt <- data.table::data.table(
    country = c("japan", "brazil", "canada"),
    value = c("1", "2", "3")
  )

  result <- sort_pipeline_stage_dt(dt)

  testthat::expect_identical(result$country, c("brazil", "canada", "japan"))
  testthat::expect_identical(result$value, c("2", "3", "1"))
})

testthat::test_that("sort_pipeline_stage_dt returns unchanged rows when no sort columns exist", {
  dt <- data.table::data.table(z = c(2, 1, 3))
  result <- sort_pipeline_stage_dt(dt)

  testthat::expect_identical(result$z, c(2, 1, 3))
})


# --- copy_as_data_table ------------------------------------------------------

testthat::test_that("copy_as_data_table returns data.table from data.frame", {
  df <- data.frame(a = 1:3)
  result <- copy_as_data_table(df)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_identical(result$a, 1:3)
})

testthat::test_that("copy_as_data_table returns deep copy of data.table", {
  dt <- data.table::data.table(a = 1:3)
  result <- copy_as_data_table(dt)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_identical(result$a, 1:3)
  testthat::expect_false(
    identical(data.table::address(result), data.table::address(dt))
  )
})

testthat::test_that("copy_as_data_table isolates from by-reference mutation", {
  dt <- data.table::data.table(a = 1:3)
  result <- copy_as_data_table(dt)

  result[, b := 10L]

  testthat::expect_true("b" %in% names(result))
  testthat::expect_false("b" %in% names(dt))
})


# --- validate_export_import --------------------------------------------------

testthat::test_that("validate_export_import accepts valid input", {
  df <- data.frame(a = 1:3)
  result <- validate_export_import(df, "test_export")

  testthat::expect_true(data.table::is.data.table(result))
})

testthat::test_that("validate_export_import errors on empty data", {
  testthat::expect_error(
    validate_export_import(data.frame(), "test_export")
  )
})


# --- get_config_string -------------------------------------------------------

testthat::test_that("get_config_string retrieves nested config value", {
  config <- list(paths = list(data = list(export = list(processed = "/tmp"))))
  result <- get_config_string(
    config,
    c("paths", "data", "export", "processed"),
    "field"
  )

  testthat::expect_identical(result, "/tmp")
})

testthat::test_that("get_config_string errors on missing path", {
  config <- list(paths = list())

  testthat::expect_error(
    get_config_string(config, c("paths", "nonexistent"), "field")
  )
})


# --- assign_environment_values -----------------------------------------------

testthat::test_that("assign_environment_values assigns named values", {
  env <- new.env(parent = emptyenv())
  result <- assign_environment_values(
    values = list(alpha = 1L, beta = "b"),
    env = env
  )

  testthat::expect_true(isTRUE(invisible(result)))
  testthat::expect_identical(env$alpha, 1L)
  testthat::expect_identical(env$beta, "b")
})

testthat::test_that("assign_environment_values handles empty lists and overwrites", {
  env <- new.env(parent = emptyenv())
  env$alpha <- 100L

  assign_environment_values(values = list(), env = env)
  assign_environment_values(values = list(alpha = 5L), env = env)

  testthat::expect_identical(env$alpha, 5L)
})

testthat::test_that("assign_environment_values errors on unnamed values", {
  env <- new.env(parent = emptyenv())

  testthat::expect_error(
    assign_environment_values(values = list(1L, 2L), env = env),
    "named|Must have names"
  )
})


# --- checkpoint functions ----------------------------------------------------

testthat::test_that("save_pipeline_checkpoint returns NULL when disabled", {
  withr::local_options(whep.checkpointing.enabled = FALSE)

  config <- list(paths = list(data = list(root = tempdir())))
  result <- save_pipeline_checkpoint(
    result = list(a = 1),
    checkpoint_name = "test_checkpoint",
    config = config
  )

  testthat::expect_null(result)
})

testthat::test_that("load_pipeline_checkpoint returns NULL when disabled", {
  withr::local_options(whep.checkpointing.enabled = FALSE)

  config <- list(paths = list(data = list(root = tempdir())))
  result <- load_pipeline_checkpoint(
    checkpoint_name = "test_checkpoint",
    config = config
  )

  testthat::expect_null(result)
})

testthat::test_that("checkpoint round-trips data when enabled", {
  withr::local_options(whep.checkpointing.enabled = TRUE)

  config <- list(paths = list(data = list(root = tempdir())))
  test_data <- list(value = 42, name = "test")

  checkpoint_dir <- fs::path(here::here(), "data", ".checkpoints")
  withr::defer(
    if (fs::dir_exists(checkpoint_dir)) fs::dir_delete(checkpoint_dir)
  )

  save_path <- save_pipeline_checkpoint(
    result = test_data,
    checkpoint_name = "round_trip_test",
    config = config
  )

  testthat::expect_true(is.character(save_path))
  testthat::expect_true(file.exists(save_path))

  loaded <- load_pipeline_checkpoint(
    checkpoint_name = "round_trip_test",
    config = config
  )

  testthat::expect_identical(loaded, test_data)
})

testthat::test_that("load_pipeline_checkpoint returns NULL for missing checkpoint", {
  withr::local_options(whep.checkpointing.enabled = TRUE)

  config <- list(paths = list(data = list(root = tempdir())))
  result <- load_pipeline_checkpoint(
    checkpoint_name = "nonexistent_checkpoint",
    config = config
  )

  testthat::expect_null(result)
})

testthat::test_that("clear_pipeline_checkpoints removes directory", {
  withr::local_options(whep.checkpointing.enabled = TRUE)

  config <- list(paths = list(data = list(root = tempdir())))
  checkpoint_dir <- fs::path(here::here(), "data", ".checkpoints")

  save_pipeline_checkpoint(
    result = list(value = 42),
    checkpoint_name = "clear_test",
    config = config
  )

  testthat::expect_true(fs::dir_exists(checkpoint_dir))

  clear_pipeline_checkpoints(config)

  testthat::expect_false(fs::dir_exists(checkpoint_dir))
})


# --- map_with_progress -------------------------------------------------------

testthat::test_that("map_with_progress maps without progress when disabled", {
  result <- map_with_progress(
    1:3,
    \(x) x * 2,
    enable_progress = FALSE
  )

  testthat::expect_equal(result, list(2, 4, 6))
})

testthat::test_that("map_with_progress handles empty input", {
  result <- map_with_progress(
    list(),
    \(x) x,
    enable_progress = FALSE
  )

  testthat::expect_identical(result, list())
})


# --- generate_export_path ----------------------------------------------------

testthat::test_that("generate_export_path builds correct paths", {
  config <- build_test_config()

  processed_path <- generate_export_path(
    config,
    "food balance",
    "processed",
    use_here = FALSE
  )

  testthat::expect_match(basename(processed_path), "food_balance\\.xlsx$")
})


# --- format_elapsed_time ----------------------------------------------------

testthat::test_that("format_elapsed_time formats sub-minute durations as seconds", {
  testthat::expect_identical(format_elapsed_time(0), "0.0s")
  testthat::expect_identical(format_elapsed_time(0.5), "0.5s")
  testthat::expect_identical(format_elapsed_time(59.9), "59.9s")
})

testthat::test_that("format_elapsed_time formats minutes and seconds", {
  testthat::expect_identical(format_elapsed_time(60), "1m 0s")
  testthat::expect_identical(format_elapsed_time(90), "1m 30s")
  testthat::expect_identical(format_elapsed_time(125), "2m 5s")
})

testthat::test_that("format_elapsed_time formats hours and minutes", {
  testthat::expect_identical(format_elapsed_time(3600), "1h 0m")
  testthat::expect_identical(format_elapsed_time(3661), "1h 1m")
  testthat::expect_identical(format_elapsed_time(7200), "2h 0m")
})

testthat::test_that("format_elapsed_time rejects invalid input", {
  testthat::expect_error(format_elapsed_time(-1))
  testthat::expect_error(format_elapsed_time("10"))
  testthat::expect_error(format_elapsed_time(Inf))
})


# --- drop_na_value_rows ------------------------------------------------------

testthat::test_that("drop_na_value_rows removes rows where value is NA", {
  dt <- data.table::data.table(
    country = c("Japan", "France", "Italy"),
    value = c("100", NA_character_, "300")
  )

  withr::with_options(list(whep.drop_na_values = TRUE), {
    result <- drop_na_value_rows(dt)
    testthat::expect_equal(nrow(result), 2L)
    testthat::expect_true(all(!is.na(result$value)))
  })
})

testthat::test_that("drop_na_value_rows skips filtering when option is FALSE", {
  dt <- data.table::data.table(
    country = c("Japan", "France"),
    value = c("100", NA_character_)
  )

  withr::with_options(list(whep.drop_na_values = FALSE), {
    result <- drop_na_value_rows(dt)
    testthat::expect_equal(nrow(result), 2L)
  })
})

testthat::test_that("drop_na_value_rows defaults to TRUE when option is unset", {
  dt <- data.table::data.table(
    country = c("Japan", "France"),
    value = c("100", NA_character_)
  )

  withr::with_options(list(whep.drop_na_values = NULL), {
    result <- drop_na_value_rows(dt)
    testthat::expect_equal(nrow(result), 1L)
  })
})

testthat::test_that("drop_na_value_rows returns unchanged dt when no NAs", {
  dt <- data.table::data.table(
    country = c("Japan", "France"),
    value = c("100", "200")
  )

  result <- drop_na_value_rows(dt)
  testthat::expect_equal(nrow(result), 2L)
})

testthat::test_that("drop_na_value_rows preserves data.table class", {
  dt <- data.table::data.table(
    country = c("Japan", "France", "Italy"),
    value = c("100", NA_character_, "300")
  )

  result <- drop_na_value_rows(dt)
  testthat::expect_true(data.table::is.data.table(result))
})

testthat::test_that("drop_na_value_rows works with custom column name", {
  dt <- data.table::data.table(
    country = c("Japan", "France", "Italy"),
    amount = c("100", NA_character_, "300")
  )

  result <- drop_na_value_rows(dt, value_column = "amount")
  testthat::expect_equal(nrow(result), 2L)
})

testthat::test_that("drop_na_value_rows returns dt when column not found", {
  dt <- data.table::data.table(
    country = c("Japan", "France"),
    value = c("100", "200")
  )

  result <- drop_na_value_rows(dt, value_column = "nonexistent")
  testthat::expect_equal(nrow(result), 2L)
})

testthat::test_that("drop_na_value_rows handles empty data.table", {
  dt <- data.table::data.table(country = character(0), value = character(0))
  result <- drop_na_value_rows(dt)
  testthat::expect_equal(nrow(result), 0L)
})

testthat::test_that("drop_na_value_rows is idempotent", {
  dt <- data.table::data.table(
    country = c("Japan", "France", "Italy"),
    value = c("100", NA_character_, "300")
  )

  first_pass <- drop_na_value_rows(dt)
  second_pass <- drop_na_value_rows(first_pass)
  testthat::expect_equal(nrow(second_pass), 2L)
  testthat::expect_identical(first_pass, second_pass)
})

testthat::test_that("drop_na_value_rows uses explicit row subsetting for data.frame input", {
  df <- data.frame(
    country = c("Japan", "France", "Italy"),
    value = c("100", NA_character_, "300"),
    stringsAsFactors = FALSE
  )

  result <- drop_na_value_rows(df)
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_true(all(!is.na(result$value)))
})
