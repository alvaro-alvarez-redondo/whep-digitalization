#' @title Synthetic data module
#' @description Synthetic data generators and lightweight benchmark
#'   configuration helpers used by the performance framework.
#' @keywords internal
#' @noRd
NULL

# ── 2. synthetic data generators ────────────────────────────────────────────

#' @title Synthetic commodity labels
#' @description Internal pool of commodity labels used to generate synthetic rows.
#' @keywords internal
#' @noRd
.ca_commodity <- c(
  "cereals",
  "oilseeds",
  "pulses",
  "fruits",
  "vegetables",
  "sugar",
  "roots",
  "cotton",
  "tobacco",
  "fibres"
)

#' @title Synthetic variable labels
#' @description Internal pool of variable labels used to generate synthetic rows.
#' @keywords internal
#' @noRd
.ca_variables <- c(
  "commodityion",
  "yield",
  "area_harvested",
  "import_quantity",
  "export_quantity",
  "feed",
  "seed",
  "stock_variation"
)

#' @title Synthetic unit labels
#' @description Internal pool of unit labels used to generate synthetic rows.
#' @keywords internal
#' @noRd
.ca_units <- c("tonnes", "kg_ha", "ha", "usd", "1000_usd", "head")

#' @title Synthetic continent labels
#' @description Internal pool of continent labels used to generate synthetic rows.
#' @keywords internal
#' @noRd
.ca_continents <- c("asia", "europe", "africa", "americas", "oceania")

#' @title Synthetic country labels
#' @description Internal pool of country labels used to generate synthetic rows.
#' @keywords internal
#' @noRd
.ca_countries <- paste0("country_", formatC(1:80, width = 2L, flag = "0"))

#' @title Make synthetic wide data table
#' @description Generate a wide-format data.table with n rows and n_years
#'   year columns.
#' @param n An integer. Number of rows to generate.
#' @param n_years An integer. Number of year columns to generate.
#' @return A data.table containing key columns and sequential year columns.
make_wide_dt <- function(n, n_years = 10L) {
  year_cols <- as.character(seq(2000L, 2000L + n_years - 1L))
  dt <- data.table::data.table(
    commodity = sample(.ca_commodity, n, replace = TRUE),
    variable = sample(.ca_variables, n, replace = TRUE),
    unit = sample(.ca_units, n, replace = TRUE),
    continent = sample(.ca_continents, n, replace = TRUE),
    country = sample(.ca_countries, n, replace = TRUE),
    footnotes = sample(
      c(NA_character_, "e", "f", "p"),
      n,
      replace = TRUE,
      prob = c(0.7, 0.1, 0.1, 0.1)
    )
  )
  year_vals <- matrix(
    ifelse(
      stats::runif(n * n_years) < 0.9,
      as.character(round(stats::runif(n * n_years, 0, 1e6), 1)),
      NA_character_
    ),
    nrow = n,
    ncol = n_years
  )
  for (i in seq_along(year_cols)) {
    data.table::set(dt, j = year_cols[[i]], value = year_vals[, i])
  }
  return(dt)
}

#' @title Make synthetic long data table
#' @description Generate a long-format data.table that matches the expected
#'   benchmark schema.
#' @param n An integer. Number of rows to generate.
#' @param na_fraction A numeric scalar in [0, 1]. Share of rows with missing
#'   value entries.
#' @param dup_fraction A numeric scalar in [0, 1]. Share of duplicate rows.
#' @return A data.table with long-format schema columns.
make_long_dt <- function(n, na_fraction = 0.0, dup_fraction = 0.0) {
  n_dup <- as.integer(floor(n * dup_fraction))
  n_orig <- n - n_dup

  dt <- data.table::data.table(
    commodity = sample(.ca_commodity, n_orig, replace = TRUE),
    variable = sample(.ca_variables, n_orig, replace = TRUE),
    unit = sample(.ca_units, n_orig, replace = TRUE),
    continent = sample(.ca_continents, n_orig, replace = TRUE),
    country = sample(.ca_countries, n_orig, replace = TRUE),
    year = sample(as.character(1990L:2020L), n_orig, replace = TRUE),
    value = ifelse(
      stats::runif(n_orig) < na_fraction,
      NA_character_,
      as.character(round(stats::runif(n_orig, 0, 1e6), 2))
    ),
    notes = NA_character_,
    yearbook = sample(
      c("yearbook_2020", "yearbook_2021"),
      n_orig,
      replace = TRUE
    ),
    document = sample(
      paste0("file_", formatC(1:5, width = 2L, flag = "0"), ".xlsx"),
      n_orig,
      replace = TRUE
    ),
    footnotes = sample(
      c(NA_character_, "e", "f", "p"),
      n_orig,
      replace = TRUE,
      prob = c(0.7, 0.1, 0.1, 0.1)
    )
  )

  if (n_dup > 0L) {
    dup_idx <- sample(seq_len(n_orig), n_dup, replace = TRUE)
    dt <- data.table::rbindlist(list(dt, dt[dup_idx]))
  }

  return(dt)
}

#' @title Make synthetic numeric character vector
#' @description Create a character vector suitable for numeric coercion
#'   benchmarking.
#' @param n An integer. Length of output vector.
#' @return A character vector containing numeric strings, empty strings, and NA.
make_numeric_string_vec <- function(n) {
  pool <- c(
    as.character(round(stats::runif(max(n, 100L), -1e6, 1e6), 4)),
    rep("", 5L),
    rep(NA_character_, 5L)
  )
  sample(pool, n, replace = TRUE)
}

#' @title Make benchmark pipeline configuration
#' @description Return a minimal configuration list containing only fields
#'   required by benchmarked pipeline functions.
#' @return A named list that is a subset of the full pipeline configuration.
make_benchmark_config <- function() {
  col_order <- c(
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
  list(
    column_required = c(
      "commodity",
      "variable",
      "unit",
      "continent",
      "country"
    ),
    column_id = c(
      "commodity",
      "variable",
      "unit",
      "hemisphere",
      "continent",
      "country",
      "footnotes"
    ),
    column_order = col_order,
    defaults = list(notes_value = NA_character_),
    columns = list(
      mandatory = c("commodity", "variable", "unit", "value"),
      base = c("continent", "country", "unit", "footnotes"),
      id = c(
        "commodity",
        "variable",
        "unit",
        "hemisphere",
        "continent",
        "country",
        "footnotes"
      ),
      value = c("year", "value")
    )
  )
}
