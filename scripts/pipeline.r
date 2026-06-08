# ============================================================
# Pipeline - scheduler entry point
# ============================================================


#--- Config -----------------------------------------------------

base_dir <- getwd()

# sanity check
if (!dir.exists(file.path(base_dir, "data")) ||
      !dir.exists(file.path(base_dir, "scripts"))) {
  stop("Please run this script from the project root directory.")
}

input_dir  <- file.path(base_dir, "data")
output_dir <- file.path(base_dir, "output")
log_file   <- file.path(output_dir, "task_log.txt")

script_path <- file.path(base_dir, "scripts", "quarterly_analysis.R")

if (!file.exists(script_path)) {
  stop(paste("Analysis script not found:", script_path))
}

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(input_dir, showWarnings = FALSE, recursive = TRUE)


# --- Log file ----------------------------------------------

log <- function(level, msg) {
  cat(
    sprintf(
      "%s | %-5s | %s\n",
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      level,
      msg
    ),
    file = log_file,
    append = TRUE
  )
}

log("START", "Pipeline started")

# ---- Quarter logic ----------------------------------------

today <- Sys.Date()
year  <- as.integer(format(today, "%Y"))
qnum  <- ((as.integer(format(today, "%m")) - 1) %/% 3) + 1
quarter_id <- paste0(year, "_Q", qnum)

quarter_flag <- file.path(output_dir, paste0("quarter_run_", quarter_id, ".txt"))

# ---- Idempotency gate -------------------------------------

if (file.exists(quarter_flag)) {
  log("SKIP", paste("Run skipped - already processed:", quarter_id))
  quit(status = 0) # exit early if already processed (scheduler behaviour)
}

log("INFO", paste("Starting processing for", quarter_id))


# ---- Verify and copy expected export ------------

# upstream system provides a quarterly CSV export, config-driven

expected_file <- file.path(
  input_dir,
  paste0("input_data_", quarter_id, ".csv") #Production pipeline uses quartly dated files, fallback for testing is input_data.csv
)

fallback_file <- file.path(input_dir, "input_data.csv")

if (file.exists(expected_file)) {

  file.copy(
    expected_file,
    fallback_file,
    overwrite = TRUE # Standardise input filename for downstream analysis script
  )

  log("INFO", paste("Using dated input file:", basename(expected_file)))

} else if (file.exists(fallback_file)) {

  log("INFO", "Using fallback input_data.csv")

} else {

  log(
    "ERROR",
    paste(
      "No valid input file found.",
      "Expected:", basename(expected_file),
      "or input_data.csv"
    )
  )
  stop("No valid input file available.")
}


# ---- Run the actual pipeline --------------------------------

tryCatch(
  {
    source(script_path)

    writeLines(
      c(
        paste("Quarter:", quarter_id),
        paste("Processed at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      ),
      quarter_flag
    )

    log("OK", paste("Quarter completed:", quarter_id))
  },
  error = function(e) {
    log("ERROR", e$message)
    stop(e)
  }
)
