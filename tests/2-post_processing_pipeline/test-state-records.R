# tests/2-post_processing_pipeline/test-state-records.R
# unit tests pinning the jul4 lazy stage-state records used by multi-pass
# cycle detection: sound fingerprints, lazy exact serialization, and verdicts
# identical to comparing full serializations.

source(here::here("tests", "test_helper.R"), echo = FALSE)
source(
  here::here("r", "2-postpro_pipeline", "run_postpro_pipeline.R"),
  echo = FALSE
)

build_state_dt <- function() {
  data.table::data.table(
    commodity = c("wheat", "rice", NA_character_),
    unit = c("t", "kg", "t"),
    value = c("1", "22", "333")
  )
}

# --- fingerprint_stage_state -------------------------------------------------

testthat::test_that("equal states produce equal fingerprints", {
  a <- build_state_dt()
  b <- data.table::copy(a)

  testthat::expect_identical(
    fingerprint_stage_state(a),
    fingerprint_stage_state(b)
  )
})

testthat::test_that("fingerprints react to value, NA, and shape changes", {
  base_dt <- build_state_dt()

  longer_value <- data.table::copy(base_dt)
  data.table::set(longer_value, 1L, "value", "1000")
  testthat::expect_false(identical(
    fingerprint_stage_state(base_dt),
    fingerprint_stage_state(longer_value)
  ))

  extra_na <- data.table::copy(base_dt)
  data.table::set(extra_na, 1L, "commodity", NA_character_)
  testthat::expect_false(identical(
    fingerprint_stage_state(base_dt),
    fingerprint_stage_state(extra_na)
  ))

  fewer_rows <- base_dt[1:2]
  testthat::expect_false(identical(
    fingerprint_stage_state(base_dt),
    fingerprint_stage_state(fewer_rows)
  ))
})

# --- record matching ----------------------------------------------------------

testthat::test_that("equal pass states match and report the stored pass index", {
  stored <- build_stage_state_record(build_state_dt())
  candidate <- build_stage_state_record(data.table::copy(build_state_dt()))

  repeated_pass <- find_repeated_stage_state_pass(
    state_records = list(stored),
    state_pass_indexes = 0L,
    candidate_record = candidate
  )

  testthat::expect_identical(repeated_pass, 0L)
})

testthat::test_that("different pass states do not match", {
  stored <- build_stage_state_record(build_state_dt())
  changed_dt <- build_state_dt()
  data.table::set(changed_dt, 1L, "commodity", "maize")
  candidate <- build_stage_state_record(changed_dt)

  repeated_pass <- find_repeated_stage_state_pass(
    state_records = list(stored),
    state_pass_indexes = 0L,
    candidate_record = candidate
  )

  testthat::expect_identical(repeated_pass, NA_integer_)
})

testthat::test_that("fingerprint collisions fall through to the exact compare", {
  # same per-column byte and NA counts (a<->NA swap between rows), different
  # content: the cheap fingerprint cannot separate these, the serialized
  # comparison must
  left_dt <- data.table::data.table(commodity = c("a", NA), unit = c("t", "t"))
  right_dt <- data.table::data.table(commodity = c(NA, "a"), unit = c("t", "t"))

  left_record <- build_stage_state_record(left_dt)
  right_record <- build_stage_state_record(right_dt)

  testthat::expect_identical(left_record$fingerprint, right_record$fingerprint)

  repeated_pass <- find_repeated_stage_state_pass(
    state_records = list(left_record),
    state_pass_indexes = 1L,
    candidate_record = right_record
  )

  testthat::expect_identical(repeated_pass, NA_integer_)
})

testthat::test_that("serialization is materialized lazily and only on collision", {
  stored <- build_stage_state_record(build_state_dt())
  testthat::expect_null(stored$serialized)

  # a fingerprint mismatch must not serialize either side
  changed_dt <- build_state_dt()
  data.table::set(changed_dt, 1L, "value", "999999")
  candidate <- build_stage_state_record(changed_dt)
  find_repeated_stage_state_pass(
    state_records = list(stored),
    state_pass_indexes = 0L,
    candidate_record = candidate
  )
  testthat::expect_null(stored$serialized)
  testthat::expect_null(candidate$serialized)

  # a fingerprint collision materializes the exact form on both sides
  twin <- build_stage_state_record(data.table::copy(build_state_dt()))
  find_repeated_stage_state_pass(
    state_records = list(stored),
    state_pass_indexes = 0L,
    candidate_record = twin
  )
  testthat::expect_false(is.null(stored$serialized))
  testthat::expect_false(is.null(twin$serialized))
})

testthat::test_that("record verdicts agree with full-serialization verdicts", {
  states <- list(
    build_state_dt(),
    {
      changed <- build_state_dt()
      data.table::set(changed, 2L, "unit", "g")
      changed
    },
    data.table::copy(build_state_dt())
  )

  for (left_index in seq_along(states)) {
    for (right_index in seq_along(states)) {
      serialize_verdict <- identical(
        serialize_stage_state_signature(data.table::copy(states[[left_index]])),
        serialize_stage_state_signature(data.table::copy(states[[right_index]]))
      )

      record_verdict <- !is.na(find_repeated_stage_state_pass(
        state_records = list(build_stage_state_record(states[[left_index]])),
        state_pass_indexes = 0L,
        candidate_record = build_stage_state_record(states[[right_index]])
      ))

      testthat::expect_identical(record_verdict, serialize_verdict)
    }
  }
})
