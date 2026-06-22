# Autocode performance benchmark (read-only metric for the autocode loop).
#
# Measures wall-clock of the CPU-bound post-processing stage
# (run_postpro_pipeline_batch) on the REAL imported WHEP dataset. Import is
# I/O-bound (readxl) and not the optimization target, so the imported raw
# data.table is cached once under data/.autocode_bench/ (gitignored) and reused.
#
# Output (parsed by autocode.toml [metrics.performance]):
#   POSTPRO_SECONDS: <min elapsed over reps>
#   POSTPRO_ROWS:    <rows fed to postpro>
#
# Env knobs:
#   WHEP_BENCH_ROWS  target row count for a deterministic systematic subset
#                    (0 or unset = full dataset)
#   WHEP_BENCH_REPS  timed repetitions; reported value is the MIN (default 2)
suppressWarnings(suppressMessages({
  library(here)
  library(data.table)
}))

options(
  whep.run_pipeline.auto = FALSE,
  whep.run_general_pipeline.auto = FALSE,
  whep.run_import_pipeline.auto = FALSE,
  whep.run_postpro_pipeline.auto = FALSE,
  whep.run_export_pipeline.auto = FALSE,
  whep.progress.enabled = FALSE
)

root <- here::here("r")
source(file.path(root, "run_pipeline.R"), echo = FALSE)
source(file.path(root, "0-general_pipeline", "run_general_pipeline.R"), echo = FALSE)
source(file.path(root, "1-import_pipeline", "run_import_pipeline.R"), echo = FALSE)
source(file.path(root, "2-postpro_pipeline", "run_postpro_pipeline.R"), echo = FALSE)

cache_dir <- here::here("data", ".autocode_bench")
raw_path <- file.path(cache_dir, "raw_dt.rds")

# Always run the general stage: it sources the shared helpers (assert_or_abort,
# normalize_string, ...) and loads dependency namespaces the postpro stage needs,
# and builds the config. This is cheap (~2-3s) relative to import/postpro.
config <- run_general_pipeline()

# Cache only the expensive import output (the readxl-bound stage we are NOT
# optimizing) so each benchmark run reuses the same real raw dataset.
if (file.exists(raw_path)) {
  raw_dt <- data.table::as.data.table(readRDS(raw_path))
} else {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  import_result <- run_import_pipeline(config)
  raw_dt <- data.table::as.data.table(import_result$data)
  saveRDS(raw_dt, raw_path)
}

# Deterministic systematic subset (preserves diversity across the sorted file
# order) when a target row count is requested.
target_rows <- suppressWarnings(as.integer(Sys.getenv("WHEP_BENCH_ROWS", "0")))
if (!is.na(target_rows) && target_rows > 0L && target_rows < nrow(raw_dt)) {
  stride <- max(1L, as.integer(floor(nrow(raw_dt) / target_rows)))
  keep <- seq.int(1L, nrow(raw_dt), by = stride)
  raw_dt <- raw_dt[keep]
}

reps <- suppressWarnings(as.integer(Sys.getenv("WHEP_BENCH_REPS", "2")))
if (is.na(reps) || reps < 1L) reps <- 2L

# Keep timing comparable run-to-run: hold caches at their constant defaults.
config$postpro$runtime_cache$enabled <- FALSE
config$postpro$schema_validation_cache$enabled <- FALSE

elapsed <- numeric(reps)
postpro_rows <- NA_integer_
for (i in seq_len(reps)) {
  input_dt <- data.table::copy(raw_dt)
  t <- system.time(out <- run_postpro_pipeline_batch(input_dt, config))
  elapsed[i] <- t[["elapsed"]]
  postpro_rows <- nrow(out)
}

cat(sprintf("POSTPRO_SECONDS: %.3f\n", min(elapsed)))
cat(sprintf("POSTPRO_ROWS: %d\n", postpro_rows))
cat(sprintf("POSTPRO_ALL_REPS: %s\n", paste(sprintf("%.2f", elapsed), collapse = ",")))
