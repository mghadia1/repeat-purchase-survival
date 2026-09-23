#!/usr/bin/env Rscript
# Usage:
#   Rscript scripts/run.R download            # fetch + checksum the UCI workbook
#   Rscript scripts/run.R analyze [out_dir]   # everything else -> outputs/

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0 || !args[1] %in% c("download", "analyze")) {
  stop("usage: Rscript scripts/run.R download | analyze [out_dir]")
}
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

if (args[1] == "download") {
  cat(download_workbook(), "\n")
  quit(save = "no")
}

out <- if (length(args) >= 2) args[2] else "outputs"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
workbook <- verify_file(file.path("data/raw", workbook_name), workbook_sha256)

# ---- data -------------------------------------------------------------------
loaded <- load_lines(workbook)
sales <- customer_sales(loaded$lines)
data_end <- max(sales$day)
FIRST_SEEN_FROM <- as.Date("2010-03-01")   # guard against left-censored "new" customers
customers <- build_customers(sales, data_end, FIRST_SEEN_FROM)

# ---- 1. what ignoring censoring does ------------------------------------------
bias <- censoring_bias(customers)
overall <- survfit(Surv(time, returned) ~ 1, data = customers)

# sensitivity of the headline to the left-censoring guard
sensitivity <- do.call(rbind, lapply(as.Date(c("2009-12-01", "2010-03-01", "2010-06-01")), function(from) {
  cust <- build_customers(sales, data_end, from)
  fit <- survfit(Surv(time, returned) ~ 1, data = cust)
  data.frame(first_seen_from = as.character(from), customers = nrow(cust),
             median_days = km_median(fit), returned_by_90 = km_at(fit, 90)$returned)
}))

# ---- 2. groups -----------------------------------------------------------------
customers$value_group <- cut(customers$first_value, quantile(customers$first_value, c(0, 1/3, 2/3, 1)),
                             include.lowest = TRUE, labels = c("low", "middle", "high"))
customers$market <- ifelse(customers$uk == 1, "UK", "outside UK")
by_value <- group_curves(customers, "value_group")
by_market <- group_curves(customers, "market")
by_season <- group_curves(customers, "holiday_season")

# ---- 3. Cox model, fit on 70% of customers, evaluated on the other 30% ------------
parts <- split_customers(customers)
model <- fit_cox(parts$train)
ratios <- hazard_ratios(model)
ph <- ph_check(model)
# Stratifying on the season lets its effect change over time instead of forcing
# one hazard ratio - the fix if the proportional-hazards check fails for it.
model_strat <- fit_cox(parts$train, Surv(time, returned) ~ log_first_value + log_first_items + uk + strata(holiday_season))
c_main <- held_out_concordance(model, parts$test)
c_strat <- held_out_concordance(model_strat, parts$test)
calibration <- calibration_at(model, parts$test, 180)

# ---- outputs ---------------------------------------------------------------------
write.csv(bias, file.path(out, "censoring_bias.csv"), row.names = FALSE)
write.csv(sensitivity, file.path(out, "left_censoring_sensitivity.csv"), row.names = FALSE)
write.csv(ratios, file.path(out, "hazard_ratios.csv"), row.names = FALSE)
write.csv(ph, file.path(out, "ph_check.csv"), row.names = FALSE)
write.csv(calibration, file.path(out, "calibration_180d.csv"), row.names = FALSE)
for (g in list(list("value", by_value), list("market", by_market), list("season", by_season))) {
  write.csv(as.data.frame(g[[2]]$medians), file.path(out, sprintf("km_by_%s.csv", g[[1]])))
}

labels <- c(log_first_value = "First order value (per 2.7x)", log_first_items = "Distinct items in first order (per 2.7x)",
            uk = "UK customer", holiday_season = "First bought Sep-Nov")
save_plot <- function(p, name, w = 7, h = 4) ggplot2::ggsave(file.path(out, name), p, width = w, height = h, dpi = 150, bg = "white")
save_plot(plot_censoring_bias(bias), "censoring_bias.png", h = 4.4)
save_plot(plot_km(by_value$fit, "Time to second purchase by first-order value (tertiles)",
                  c("value_group=low" = "low", "value_group=middle" = "middle", "value_group=high" = "high")), "km_by_value.png")
save_plot(plot_km(by_season$fit, "Time to second purchase: first bought Sep-Nov vs other months",
                  c("holiday_season=0" = "Dec-Aug", "holiday_season=1" = "Sep-Nov")), "km_by_season.png")
save_plot(plot_calibration(calibration, 180), "calibration_180d.png", w = 5, h = 5)
save_plot(plot_hazard_ratios(ratios, labels), "hazard_ratios.png", h = 3)

summary <- list(
  lines_after_overlap = nrow(loaded$lines), overlap_rows_removed = loaded$overlap_rows_removed,
  customers = nrow(customers), returned = sum(customers$returned),
  censored = sum(customers$returned == 0), data_end = as.character(data_end),
  first_seen_from = as.character(FIRST_SEEN_FROM),
  median_days_to_return = km_median(overall),
  censoring_bias = bias, left_censoring_sensitivity = sensitivity,
  logrank = list(value = by_value[c("logrank_chisq", "logrank_p")],
                 market = by_market[c("logrank_chisq", "logrank_p")],
                 season = by_season[c("logrank_chisq", "logrank_p")]),
  medians = list(value = by_value$medians, market = by_market$medians, season = by_season$medians),
  train_customers = nrow(parts$train), test_customers = nrow(parts$test),
  hazard_ratios = ratios, ph_check = ph,
  held_out_c_index = c_main, held_out_c_index_stratified = c_strat,
  calibration_180d = calibration
)
jsonlite::write_json(summary, file.path(out, "summary.json"), auto_unbox = TRUE, digits = 5, pretty = TRUE)
cat(jsonlite::toJSON(summary[c("customers", "returned", "censored", "median_days_to_return",
                               "held_out_c_index", "held_out_c_index_stratified")], auto_unbox = TRUE, pretty = TRUE), "\n")
