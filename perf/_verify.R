# Behavior-preservation harness. The postpro stage is bit-deterministic
# run-to-run (verified), so we compare EXACT, UNSORTED, column-by-column against
# a golden capture. Comparing raw column vectors (via as.list) sidesteps
# data.table attribute noise and locale-dependent base-R sorting.
#
#   Rscript perf/_verify.R          # capture if missing, else compare
#   Rscript perf/_verify.R reset    # force re-capture
suppressWarnings(suppressMessages({ library(here); library(data.table) }))
options(
  whep.run_pipeline.auto = FALSE, whep.run_general_pipeline.auto = FALSE,
  whep.run_import_pipeline.auto = FALSE, whep.run_postpro_pipeline.auto = FALSE,
  whep.run_export_pipeline.auto = FALSE, whep.progress.enabled = FALSE
)
root <- here::here("r")
source(file.path(root, "run_pipeline.R"), echo = FALSE)
source(file.path(root, "0-general_pipeline", "run_general_pipeline.R"), echo = FALSE)
source(file.path(root, "1-import_pipeline", "run_import_pipeline.R"), echo = FALSE)
source(file.path(root, "2-postpro_pipeline", "run_postpro_pipeline.R"), echo = FALSE)
config <- run_general_pipeline()
raw_dt <- data.table::as.data.table(readRDS(here::here("data", ".autocode_bench", "raw_dt.rds")))
stride <- max(1L, as.integer(floor(nrow(raw_dt) / 120000L)))
raw_dt <- raw_dt[seq.int(1L, nrow(raw_dt), by = stride)]
config$postpro$runtime_cache$enabled <- FALSE
config$postpro$schema_validation_cache$enabled <- FALSE

# Recursively blank wall-clock timestamps so runs at different times still
# compare equal on everything that is behavior.
scrub <- function(x) {
  ts_rx <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}"
  if (is.list(x)) {
    nm <- names(x)
    for (i in seq_along(x)) {
      if (!is.null(nm) && grepl("timestamp", nm[i], ignore.case = TRUE)) x[[i]] <- "<ts>"
      else x[[i]] <- scrub(x[[i]])
    }
    return(x)
  }
  if (is.character(x)) x[grepl(ts_rx, x)] <- "<ts>"
  x
}

out <- run_postpro_pipeline_batch(data.table::copy(raw_dt), config)
diag <- attr(out, "pipeline_diagnostics")
fp <- list(
  ncol = ncol(out), nrow = nrow(out), colnames = names(out),
  cols = as.list(out),            # plain column vectors (exact, unsorted)
  diag = scrub(diag)
)

golden_path <- here::here("data", ".autocode_bench", "golden_fp.rds")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1 && args[[1]] == "reset" && file.exists(golden_path)) file.remove(golden_path)

if (!file.exists(golden_path)) {
  saveRDS(fp, golden_path)
  cat(sprintf("CAPTURED golden: %d rows x %d cols\n", fp$nrow, fp$ncol))
} else {
  g <- readRDS(golden_path)
  ok <- TRUE
  chk <- function(label, a, b) {
    res <- identical(a, b)
    if (!res) { ok <<- FALSE; cat(sprintf("  [DIFF] %s\n", label)) }
    res
  }
  cat("=== VERIFY vs golden (exact, unsorted) ===\n")
  chk("ncol", fp$ncol, g$ncol); chk("nrow", fp$nrow, g$nrow)
  chk("colnames", fp$colnames, g$colnames)
  if (identical(fp$colnames, g$colnames)) {
    for (cn in fp$colnames) chk(paste0("col:", cn), fp$cols[[cn]], g$cols[[cn]])
  }
  chk("diagnostics (ts-scrubbed)", fp$diag, g$diag)
  cat(if (ok) "RESULT: IDENTICAL\n" else "RESULT: DIVERGED\n")
}
