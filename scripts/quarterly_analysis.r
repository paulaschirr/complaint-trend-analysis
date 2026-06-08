suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(MASS)
})

# ------------------------------------------------------------
# 1) Load exported dataset (input data)
# ------------------------------------------------------------


base_dir  <- getwd()
input_file <- file.path(base_dir, "data", "input_data.csv")
history_dir <- file.path(output_dir, "history")


dataset <- read.csv(
  input_file,
  stringsAsFactors = FALSE,
  check.names = FALSE   # preserve original column names (including spaces)
)

if (!exists("log")) {
  output_dir <- file.path(getwd(), "output")
  log_file <- file.path(output_dir, "task_log.txt")

  log <- function(level, msg) {
    cat(
      sprintf("%s | %-5s | %s\n",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
              level,
              msg),
      file = log_file,
      append = TRUE
    )
  }
}

# ------------------------------------------------------------
# 2) Robust date parsing
# ------------------------------------------------------------

parse_date_multi <- function(x) {
  x <- trimws(x)
  out <- as.Date(x, format = "%Y-%m-%d")
  bad <- is.na(out) & !is.na(x) & nzchar(x)
  out[bad] <- as.Date(x[bad], format = "%d/%m/%Y")
  out
}

date_candidates <- c("Record Date", "Date", "Event Date")
date_col <- intersect(date_candidates, names(dataset))[1]
if (is.na(date_col)) stop("No recognised date column found.")

dataset[[date_col]] <- parse_date_multi(dataset[[date_col]])


# Data quality check: remove implausible future dates

future_rows <- dataset[[date_col]] > Sys.Date()

if (any(future_rows, na.rm = TRUE)) {
  n_bad <- sum(future_rows, na.rm = TRUE)
  
  log("WARN", paste(
    n_bad, "rows removed due to implausible future dates"
  ))
  
  dataset <- dataset[!future_rows, ]
}

# ------------------------------------------------------------
# Optional: shift dates to current period for testing/demo
# ------------------------------------------------------------

test_mode <- TRUE  # set to FALSE in production

if (test_mode) {
  max_date <- max(dataset[[date_col]], na.rm = TRUE)
  
  if (is.finite(max_date)) {
    shift_days <- as.numeric(Sys.Date() - max_date)
    
    dataset[[date_col]] <- dataset[[date_col]] + shift_days
    
    log("INFO", paste("Test mode: shifted dates by", shift_days, "days"))
  }
}

# ------------------------------------------------------------
# 3) Create QtrRel (-1 = last quarter, -2 = previous quarter)
# ------------------------------------------------------------

today <- Sys.Date()

# Compute current quarter start
this_year  <- as.integer(format(today, "%Y"))
this_month <- as.integer(format(today, "%m"))
this_q     <- ((this_month - 1) %/% 3) + 1
this_q_start <- as.Date(sprintf("%d-%02d-01", this_year, (this_q - 1) * 3 + 1))

# Quarter boundaries
last_q_start <- seq(this_q_start, by = "-3 months", length.out = 2)[2]
prev_q_start <- seq(this_q_start, by = "-3 months", length.out = 3)[3]

last_q_end <- this_q_start - 1
prev_q_end <- last_q_start - 1

dataset$QtrRel <- ifelse(
  dataset[[date_col]] >= last_q_start & dataset[[date_col]] <= last_q_end, -1L,
  ifelse(
    dataset[[date_col]] >= prev_q_start & dataset[[date_col]] <= prev_q_end, -2L,
    NA_integer_
  )
)

# Keep only the two quarters of interest
dataset <- dataset[dataset$QtrRel %in% c(-1L, -2L), ]

dataset$QtrRel <- factor(dataset$QtrRel, levels = c(-2, -1))

log("INFO", paste("Rows after quarter filter:", nrow(dataset)))

if (nrow(dataset) == 0) stop("No data available for the last two quarters.")

# --------------------------------------------
# 4) Input hygiene
# -------------------------------------------------

# Ensure QtrRel exists and is factor with levels -2, -1
if ("QtrRel" %in% names(dataset)) {
  dataset <- dataset %>%
    dplyr::mutate(QtrRel = factor(QtrRel, levels = c(-2, -1)))
} else {
  stop("Expected 'QtrRel' not found.")
}

# Priority/Risk column detection
priority_candidates <- c("Priority", "Levels of Priority", "Levels of Risk", "Risk")
priority_col <- intersect(priority_candidates, names(dataset))[1]
if (is.na(priority_col)) stop("No recognised priority column found.")

dataset <- dataset %>%
  dplyr::mutate(
    Risk1 = dplyr::case_when(
      trimws(as.character(.data[[priority_col]])) == "Low"    ~ 1L,
      trimws(as.character(.data[[priority_col]])) == "Medium" ~ 2L,
      trimws(as.character(.data[[priority_col]])) == "High"   ~ 3L,
      TRUE                                                     ~ NA_integer_
    ),
    Risk1 = factor(Risk1, levels = c(1L, 2L, 3L), ordered = TRUE) # map text risk levels to ordered numeric scale
  )
#drop unassessed reports

dataset <- dataset %>%
  filter(!is.na(.data[[priority_col]]) & trimws(.data[[priority_col]]) != "")


category_candidates <- c("Case Category", "Category", "Type")
category_col <- intersect(category_candidates, names(dataset))[1]
if (is.na(category_col)) stop("No recognised category column found.")


# Collapse rare categories
MIN_N_PER_CATEGORY <- 100L
cat_sizes <- dataset %>% count(.data[[category_col]], name = "n_total")

dataset <- dataset %>%
  left_join(cat_sizes, by = category_col) %>%
  mutate(Category = ifelse(n_total >= MIN_N_PER_CATEGORY,
                           as.character(.data[[category_col]]), "Other"),
         Category = factor(Category))


# ------------------------------------------------------------
# 5) Run Analysis 1 (category distribution + chi-square)
# ------------------------------------------------------------

log("INFO", "Running category delta analysis")

# =========================
# 5.1 Contingency table & overall test
# =========================

# Tidy long format summary for proportions
count_long <- dataset %>%
  dplyr::count(Category, QtrRel, name = "N") %>%
  dplyr::group_by(QtrRel) %>%
  dplyr::mutate(Prop = N / sum(N)) %>%
  dplyr::ungroup()

# Contingency matrix for chisq.test
tab <- xtabs(~ Category + QtrRel, data = dataset)

# First pass: get expected counts only
chisq0 <- suppressWarnings(chisq.test(tab))

#Don't run if there isn't enough data
if (nrow(tab) < 2 || ncol(tab) < 2) {
  stop("Insufficient variation for chi-square analysis.")
}

# Decide whether Monte Carlo is needed
use_sim <- any(chisq0$expected < 5)

# Final test: run with the chosen method
chisq_res <- try(
  if (use_sim) {
    chisq.test(tab, simulate.p.value = TRUE, B = 10000)
  } else {
    chisq0
  },
  silent = TRUE
)

# Fallback if something breaks
if (inherits(chisq_res, "try-error")) {
  chisq_res <- suppressWarnings(chisq.test(tab))
}

# Cramer's V
chisq_stat <- as.numeric(chisq_res$statistic)
n_total    <- sum(tab)
k          <- min(nrow(tab), ncol(tab))
cramers_v  <- if (n_total > 0 && k > 1) sqrt(chisq_stat / (n_total * (k - 1))) else NA_real_

overall_test_df <- data.frame(
  statistic = chisq_stat,
  df        = as.numeric(chisq_res$parameter),
  p_value   = as.numeric(chisq_res$p.value),
  cramers_v = cramers_v,
  stringsAsFactors = FALSE
)

overall_significant <- !is.na(overall_test_df$p_value) &&
                       overall_test_df$p_value < 0.05
overall_effect_present <- overall_significant &&
                          overall_test_df$cramers_v >= 0.1  # small effect threshold


log("INFO",
  paste("Shift in category distribution (chi-square significant):", overall_significant))

log("INFO",
  paste("Overall effect present (Cramer's V >= 0.1):", overall_effect_present))

# =========================
# 5.2 By-category summary (counts, proportions, deltas)
# =========================

by_cat <- count_long %>%
  tidyr::pivot_wider(
    names_from  = QtrRel,
    values_from = c(N, Prop),
    names_sep   = "_",
    values_fill = 0
  ) %>%
  # Rename to clearer labels: prev = previous quarter (QtrRel-2), last = most recent completed quarter (QtrRel-1)
  dplyr::rename(
    N_prev   = `N_-2`,
    N_last   = `N_-1`,
    Prop_prev = `Prop_-2`,
    Prop_last = `Prop_-1`
  ) %>%
  dplyr::mutate(
    Delta_Prop = Prop_last - Prop_prev
  )

# Totals per quarter
n_m2 <- sum(by_cat$N_prev)
n_m1 <- sum(by_cat$N_last)


if (n_m1 == 0 || n_m2 == 0) stop("One or both quarters have zero records.")

# Compute analytic CIs for Δ = p_-1 - p_-2, p-values, and Significant flag
per_cat_dp <- by_cat %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    # Ensure Delta_Prop matches counts
    Delta_Prop_chk = N_last / n_m1 - N_prev / n_m2,

    test = list(suppressWarnings(
      prop.test(x = c(N_last, N_prev), n = c(n_m1, n_m2), correct = FALSE)
    )),
    dp_CI_low  = unname(test$conf.int[1]),
    dp_CI_high = unname(test$conf.int[2]),
    dp_p_value = unname(test$p.value),

    # Visual flag: CI excludes 0
    Significant = dp_CI_low > 0 | dp_CI_high < 0
  ) %>%
  dplyr::ungroup() %>%
  dplyr::mutate(
    # sanity check: ensure stored Delta_Prop equals the count-based one
    Delta_Prop = ifelse(is.finite(Delta_Prop) & !is.na(Delta_Prop), Delta_Prop, Delta_Prop_chk)
  ) %>%
  dplyr::select(Category, N_prev, N_last, Prop_prev, Prop_last,
                Delta_Prop, dp_CI_low, dp_CI_high, dp_p_value, Significant)

# Adjust for multiple testing (FDR/BH)
per_cat_dp <- per_cat_dp %>%
  dplyr::mutate(
    p_adj = p.adjust(dp_p_value, method = "BH"),
    Significant_BH = dplyr::case_when(p_adj < 0.05 ~ "Yes", TRUE ~ "No")
  )

# output 
by_cat_final <- per_cat_dp %>%
  dplyr::arrange(dplyr::desc(abs(Delta_Prop)))

# ------------------------------------------------------------
# 6) Run Analysis 2 (risk model + bootstrap)
# ------------------------------------------------------------

log("INFO", "Running risk bootstrap model")

# =========================
# 6.1 Helper: safe delta from predicted probs for a bootstrap sample
# =========================

boot_delta <- function(data, idx) {
  # Subsample with replacement
  d <- data[idx, , drop = FALSE]

  # Must have at least 2 Risk1 levels and both QtrRel levels to fit/compare
  has_two_risk_levels <- length(stats::na.omit(unique(d$Risk1))) >= 2
  has_both_quarters   <- all(levels(data$QtrRel) %in% unique(d$QtrRel))
  if (!has_two_risk_levels || !has_both_quarters) {
    # Return NA Delta per Category in this sample to keep bootstrap shape
    return(d %>%
             dplyr::distinct(Category) %>%
             dplyr::mutate(Delta = NA_real_))
  }

  # Fit ordered logit
  m <- try(
    MASS::polr(
      Risk1 ~ Category * QtrRel,
      data = d,
      Hess = TRUE,
      na.action = stats::na.omit
    ),
    silent = TRUE
  )
  if (inherits(m, "try-error")) {
    return(d %>%
             dplyr::distinct(Category) %>%
             dplyr::mutate(Delta = NA_real_))
  }

  # Prediction grid
  newdata <- d %>%
    dplyr::distinct(Category, QtrRel) %>%
    stats::na.omit()

  # If prediction grid lost a quarter, bail out for this replicate
  if (!all(levels(data$QtrRel) %in% unique(newdata$QtrRel))) {
    return(d %>%
             dplyr::distinct(Category) %>%
             dplyr::mutate(Delta = NA_real_))
  }

  probs <- try(stats::predict(m, newdata = newdata, type = "probs"), silent = TRUE)
  if (inherits(probs, "try-error")) {
    return(d %>%
             dplyr::distinct(Category) %>%
             dplyr::mutate(Delta = NA_real_))
  }

  pred_df <- dplyr::bind_cols(newdata, as.data.frame(probs, stringsAsFactors = FALSE)) %>%
    # Robust Medium+ probability: sum existing columns among "2","3"
    dplyr::mutate(P_MedPlus = rowSums(dplyr::select(., dplyr::any_of(c("2","3"))), na.rm = TRUE))

  # Widen to quarters; ensure both columns exist; don't silently impute with 0
  wide <- pred_df %>%
    dplyr::select(Category, QtrRel, P_MedPlus) %>%
    tidyr::pivot_wider(
      names_from  = QtrRel,
      values_from = P_MedPlus
    )

  # Ensure both quarter columns are present; if not, add NA columns
  for (col in c("-1", "-2")) {
    if (!col %in% names(wide)) wide[[col]] <- NA_real_
  }

  wide %>%
    dplyr::mutate(Delta = `-1` - `-2`) %>%
    dplyr::select(Category, Delta)
}
# =========================
#  6.2 Bootstrap CIs for model-based Delta
# =========================

set.seed(123)

B <- 500L
n <- nrow(dataset)
# If dataset is small, reduce B slightly
if (is.finite(n) && n < 1000 && B > 300) B <- 300L

boot_res <- lapply(seq_len(B), function(i) {
  idx <- sample.int(n, size = n, replace = TRUE)
  boot_delta(dataset, idx)
})

boot_df <- dplyr::bind_rows(boot_res, .id = "rep")

delta_ci <- boot_df %>%
  dplyr::group_by(Category) %>%
  dplyr::summarise(
    Delta_est = mean(Delta, na.rm = TRUE),
    CI_low    = stats::quantile(Delta, 0.025, na.rm = TRUE, names = FALSE),
    CI_high   = stats::quantile(Delta, 0.975, na.rm = TRUE, names = FALSE),
    n_eff     = sum(!is.na(Delta)),
    .groups   = "drop"
  ) %>%
  dplyr::mutate(
  Significant = dplyr::case_when(
    n_eff <= 0 ~ NA_character_,
    CI_low > 0 | CI_high < 0 ~ "Yes",
    TRUE ~ "No"
  )
)
risk_shift_present <- any(delta_ci$Significant == "Yes", na.rm = TRUE)

log("INFO",
  paste("Shift in Medium+ risk categories detected:", risk_shift_present))

# =========================
# 6.3 Observed Medium+ proportions and delta
# =========================

obs_df <- dataset %>%
  dplyr::mutate(Risk1_num = as.numeric(as.character(Risk1))) %>%
  dplyr::group_by(Category, QtrRel) %>%
  dplyr::summarise(
    N = dplyr::n(),
    Obs_MedPlus = sum(Risk1_num >= 2, na.rm = TRUE) / N,
    .groups = "drop"
  )


obs_delta_df <- obs_df %>%
  dplyr::select(Category, QtrRel, Obs_MedPlus, N) %>%
  tidyr::pivot_wider(
    names_from  = QtrRel,
    values_from = c(Obs_MedPlus, N),
    names_sep   = "_"
  ) %>%
  dplyr::rename(
    Obs_MedPlus_prev = `Obs_MedPlus_-2`,
    Obs_MedPlus_last = `Obs_MedPlus_-1`,
    N_prev           = `N_-2`,
    N_last           = `N_-1`
  )

# Ensure both quarter columns exist; if not, set Obs_Delta to NA
for (col in c("Obs_MedPlus_last", "Obs_MedPlus_prev", "N_last", "N_prev")) {
  if (!col %in% names(obs_delta_df)) obs_delta_df[[col]] <- NA_real_
}


obs_delta_df <- obs_delta_df %>%
  dplyr::mutate(
    Obs_Delta = Obs_MedPlus_last - Obs_MedPlus_prev,
    N_total   = N_last + N_prev
  )

# =========================
# 6.4 Final merge & output as data.frame
# =========================

risk_final_df <- delta_ci %>%
  dplyr::left_join(obs_delta_df, by = "Category") %>%
  # Order by absolute estimated delta descending for convenience
  dplyr::arrange(dplyr::desc(abs(Delta_est)))


# ------------------------------------------------------------
# 7) Write outputs
# ------------------------------------------------------------

log("OK", "Quarterly analysis completed")

# ---- Directories ----
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
history_dir <- file.path(output_dir, "history")
dir.create(history_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Write current outputs ----
write.csv(
  by_cat_final,
  file.path(output_dir, "category_delta.csv"),
  row.names = FALSE
)

write.csv(
  risk_final_df,
  file.path(output_dir, "risk_model_delta.csv"),
  row.names = FALSE
)

# ---- Keep History ----
get_quarter_label <- function(date = Sys.Date()) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  q <- ((m - 1) %/% 3) + 1
  sprintf("%d-Q%d", y, q)
}

quarter_label <- get_quarter_label()

files_to_publish <- c(
  "category_delta.csv",
  "risk_model_delta.csv"
)

for (f in files_to_publish) {
  src <- file.path(output_dir, f)

  if (!file.exists(src)) {
    stop(paste("Expected output missing:", src))
  }

  base <- tools::file_path_sans_ext(f)
  dst_hist <- file.path(
    history_dir,
    paste0(base, "_", quarter_label, ".csv")
  )

  # overwrite in case of reruns for the same quarter
  file.copy(src, dst_hist, overwrite = TRUE)

  log("INFO", paste("Archived:", basename(dst_hist)))
}