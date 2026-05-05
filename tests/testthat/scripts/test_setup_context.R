options(
  whep.run_postpro_pipeline.auto = FALSE
)

source(
  here::here(
    "r",
    "0-general_pipeline",
    "01-setup/01-constants.R"
  ),
  echo = FALSE
)

source(here::here("r", "2-postpro_pipeline", "run_postpro_pipeline.R"), echo = FALSE)
