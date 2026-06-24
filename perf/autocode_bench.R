# Autocode performance benchmark (read-only metric for the autocode loop).
#
# Measures wall-clock of the full pipeline stages (general, import, postpro)
# on the REAL WHEP dataset. All stages are timed and reported individually;
# the composite PIPELINE_SECONDS is what autocode.toml parses, so the
# optimization loop sees the full picture and can target whichever stage has
# the most headroom.
#
# Export is excluded: it writes files to disk (side-effectful) and is
# typically a small fraction of total time.
#
# Output (parsed by autocode.toml [metrics.performance]):
#   PIPELINE_SECONDS: <min total elapsed over reps>
# Diagnostic output (not parsed, but visible for targeting):
#   GENERAL_SECONDS:  <general stage time>
#   IMPORT_SECONDS:   <import stage time (or "cached" if cached)>
#   POSTPRO_SECONDS:  <postpro stage time>
#   POSTPRO_ROWS:     <rows fed to postpro>
#
# Env knobs:
#   WHEP_BENCH_ROWS          target row count for a deterministic systematic
#                            subset (0 or unset = full dataset). Applied to
#                            the import result before postpro.
#   WHEP_BENCH_REPS          timed repetitions; reported value is the MIN
#                            (default 2)
#   WHEP_BENCH_CACHE_IMPORT  when "1", cache import output under
#                            data/.autocode_bench/ and skip re-timing import
#                            on subsequent runs. Useful for focused postpro
#                            iteration. Default "0" = time everything.
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

cache_import <- identical(Sys.getenv("WHEP_BENCH_CACHE_IMPORT", "0"), "1")
cache_dir <- here::here("data", ".autocode_bench")
raw_path <- file.path(cache_dir, "raw_dt.rds")

reps <- suppressWarnings(as.integer(Sys.getenv("WHEP_BENCH_REPS", "2")))
if (is.na(reps) || reps < 1L) reps <- 2L

# ---------------------------------------------------------------------------
# Stage timings (per-rep)
# ---------------------------------------------------------------------------
general_elapsed <- numeric(reps)
import_elapsed <- numeric(reps)
postpro_elapsed <- numeric(reps)
pipeline_elapsed <- numeric(reps)
postpro_rows <- NA_integer_
import_cached <- FALSE

for (i in seq_len(reps)) {
  # --- General ---
  t_gen <- system.time(config <- run_general_pipeline())
  general_elapsed[i] <- t_gen[["elapsed"]]

  # Keep timing comparable run-to-run: hold caches at their constant defaults.
  config$postpro$runtime_cache$enabled <- FALSE
  config$postpro$schema_validation_cache$enabled <- FALSE

  # --- Import ---
  if (cache_import && file.exists(raw_path)) {
    raw_dt <- data.table::as.data.table(readRDS(raw_path))
    import_elapsed[i] <- 0
    import_cached <- TRUE
  } else {
    t_imp <- system.time(import_result <- run_import_pipeline(config))
    import_elapsed[i] <- t_imp[["elapsed"]]
    raw_dt <- data.table::as.data.table(import_result$data)
    if (cache_import) {
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
      saveRDS(raw_dt, raw_path)
      import_cached <- TRUE
    }
  }

  # --- Subset (post-import, pre-postpro) ---
  target_rows <- suppressWarnings(
    as.integer(Sys.getenv("WHEP_BENCH_ROWS", "0"))
  )
  if (!is.na(target_rows) && target_rows > 0L && target_rows < nrow(raw_dt)) {
    stride <- max(1L, as.integer(floor(nrow(raw_dt) / target_rows)))
    keep <- seq.int(1L, nrow(raw_dt), by = stride)
    raw_dt <- raw_dt[keep]
  }

  # --- Postpro ---
  input_dt <- data.table::copy(raw_dt)
  t_pp <- system.time(out <- run_postpro_pipeline_batch(input_dt, config))
  postpro_elapsed[i] <- t_pp[["elapsed"]]
  postpro_rows <- nrow(out)

  # --- Total ---
  pipeline_elapsed[i] <- general_elapsed[i] + import_elapsed[i] +
    postpro_elapsed[i]
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
# Primary metric (parsed by autocode.toml)
cat(sprintf("PIPELINE_SECONDS: %.3f\n", min(pipeline_elapsed)))

# Per-stage diagnostics (not parsed, but visible for analysis)
cat(sprintf("GENERAL_SECONDS: %.3f\n", min(general_elapsed)))
if (import_cached) {
  cat("IMPORT_SECONDS: cached\n")
} else {
  cat(sprintf("IMPORT_SECONDS: %.3f\n", min(import_elapsed)))
}
cat(sprintf("POSTPRO_SECONDS: %.3f\n", min(postpro_elapsed)))
cat(sprintf("POSTPRO_ROWS: %d\n", postpro_rows))
cat(sprintf(
  "PIPELINE_ALL_REPS: %s\n",
  paste(sprintf("%.2f", pipeline_elapsed), collapse = ",")
))
