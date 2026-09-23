# Kaplan-Meier estimates, log-rank tests, a Cox model with a proportional-
# hazards check, and held-out evaluation.

library(survival)

km_at <- function(fit, days) {
  # P(returned by day t) = 1 - S(t), with its 95% CI (the bounds swap).
  s <- summary(fit, times = days, extend = TRUE)
  data.frame(day = days, returned = 1 - s$surv, lower = 1 - s$upper, upper = 1 - s$lower)
}

km_median <- function(fit) unname(summary(fit)$table["median"])

# Compare the naive rates with Kaplan-Meier at several horizons.
censoring_bias <- function(customers, horizons = c(30, 90, 180, 365)) {
  km <- km_at(survfit(Surv(time, returned) ~ 1, data = customers), horizons)
  naive <- t(sapply(horizons, function(h) naive_return_rate(customers, h)))
  data.frame(day = horizons, naive_all = naive[, "all_customers"],
             naive_enough_follow_up = naive[, "enough_follow_up"], kaplan_meier = km$returned,
             km_lower = km$lower, km_upper = km$upper)
}

group_curves <- function(customers, variable) {
  fit <- survfit(as.formula(paste("Surv(time, returned) ~", variable)), data = customers)
  test <- survdiff(as.formula(paste("Surv(time, returned) ~", variable)), data = customers)
  list(
    fit = fit,
    medians = summary(fit)$table[, c("records", "events", "median", "0.95LCL", "0.95UCL")],
    logrank_chisq = unname(test$chisq),
    logrank_p = pchisq(test$chisq, df = length(test$n) - 1, lower.tail = FALSE)
  )
}

split_customers <- function(customers, test_share = 0.3, seed = 2026) {
  set.seed(seed)
  test <- sample.int(nrow(customers), size = round(test_share * nrow(customers)))
  list(train = customers[-test, ], test = customers[test, ])
}

cox_formula <- Surv(time, returned) ~ log_first_value + log_first_items + uk + holiday_season

fit_cox <- function(train, formula = cox_formula) coxph(formula, data = train, x = TRUE)

hazard_ratios <- function(model) {
  s <- summary(model)
  data.frame(term = rownames(s$conf.int), hazard_ratio = s$conf.int[, "exp(coef)"],
             lower = s$conf.int[, "lower .95"], upper = s$conf.int[, "upper .95"],
             p = s$coefficients[, "Pr(>|z|)"], row.names = NULL)
}

# Schoenfeld-residual test of proportional hazards: is each covariate's effect
# constant over time? A small p-value says the hazard ratio drifts.
ph_check <- function(model) {
  z <- cox.zph(model)
  data.frame(term = rownames(z$table), chisq = z$table[, "chisq"], p = z$table[, "p"], row.names = NULL)
}

# Harrell's C on held-out customers: of comparable pairs, how often does the
# customer the model rates as faster-returning actually return first?
held_out_concordance <- function(model, test) {
  lp <- predict(model, newdata = test, type = "lp")
  c_obj <- concordance(Surv(time, returned) ~ lp, data = cbind(test, lp = lp), reverse = TRUE)
  c(c_index = unname(c_obj$concordance), se = sqrt(unname(c_obj$var)))
}

# Calibration at one horizon: predicted P(return by t) against the Kaplan-Meier
# estimate within each predicted-risk decile of the held-out customers.
calibration_at <- function(model, test, horizon, groups = 10) {
  surv <- survfit(model, newdata = test)
  predicted <- 1 - as.numeric(summary(surv, times = horizon, extend = TRUE)$surv)
  bucket <- cut(rank(predicted, ties.method = "first"), breaks = groups, labels = FALSE)
  do.call(rbind, lapply(split(seq_along(predicted), bucket), function(idx) {
    km <- km_at(survfit(Surv(time, returned) ~ 1, data = test[idx, ]), horizon)
    data.frame(group = bucket[idx[1]], n = length(idx), predicted = mean(predicted[idx]),
               observed = km$returned, lower = km$lower, upper = km$upper)
  }))
}
