# ggplot2 figures for the README and results document.

ink <- "#1f2937"
accent <- "#0e6a70"
muted <- "#9ca3af"
warn <- "#b45309"

base_theme <- function() {
  ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(colour = ink, size = 11),
                   plot.title.position = "plot", panel.grid.minor = ggplot2::element_blank(),
                   legend.position = "bottom")
}

curve_frame <- function(fit) {
  s <- summary(fit, censored = FALSE)
  strata <- if (is.null(s$strata)) factor("all") else s$strata
  starts <- data.frame(time = 0, returned = 0, lower = 0, upper = 0, strata = levels(strata))
  rbind(starts, data.frame(time = s$time, returned = 1 - s$surv, lower = 1 - s$upper,
                           upper = 1 - s$lower, strata = as.character(strata)))
}

plot_km <- function(fit, title, labels = NULL, max_day = 540) {
  frame <- curve_frame(fit)
  frame <- frame[frame$time <= max_day, ]
  if (!is.null(labels)) frame$strata <- factor(labels[frame$strata], levels = unname(labels))
  ggplot2::ggplot(frame, ggplot2::aes(time, returned, colour = strata, fill = strata)) +
    ggplot2::geom_step(linewidth = 0.8) +
    ggplot2::scale_y_continuous(labels = function(x) paste0(round(100 * x), "%"), limits = c(0, 1)) +
    ggplot2::scale_colour_manual(values = c(accent, warn, muted, ink), name = NULL) +
    ggplot2::labs(x = "Days since first purchase", y = "Share who have bought again", title = title) +
    base_theme()
}

plot_censoring_bias <- function(bias) {
  long <- rbind(
    data.frame(day = bias$day, method = "Naive: every customer, 'not yet' counted as 'never'", value = bias$naive_all),
    data.frame(day = bias$day, method = "Naive: only customers with enough follow-up", value = bias$naive_enough_follow_up),
    data.frame(day = bias$day, method = "Kaplan-Meier (uses censored customers)", value = bias$kaplan_meier)
  )
  long$method <- factor(long$method, levels = unique(long$method))
  ggplot2::ggplot(long, ggplot2::aes(factor(day), value, fill = method)) +
    ggplot2::geom_col(position = "dodge", width = 0.75) +
    ggplot2::scale_fill_manual(values = c(muted, "#d1d5db", accent), name = NULL) +
    ggplot2::scale_y_continuous(labels = function(x) paste0(round(100 * x), "%")) +
    ggplot2::guides(fill = ggplot2::guide_legend(ncol = 1)) +
    ggplot2::labs(x = "Within N days of the first purchase", y = "Share who bought again",
                  title = "The same question, three answers: what ignoring censoring does") +
    base_theme()
}

plot_calibration <- function(calibration, horizon) {
  top <- max(c(calibration$predicted, calibration$upper)) * 1.05
  ggplot2::ggplot(calibration, ggplot2::aes(predicted, observed)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = muted) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = lower, ymax = upper), width = 0, colour = muted) +
    ggplot2::geom_point(colour = accent, size = 2) +
    ggplot2::coord_equal(xlim = c(0, top), ylim = c(0, top)) +
    ggplot2::labs(x = sprintf("Predicted P(buy again within %d days)", horizon),
                  y = "Kaplan-Meier observed (95% CI)",
                  title = sprintf("Held-out calibration at %d days, by predicted-risk decile", horizon)) +
    base_theme()
}

plot_hazard_ratios <- function(ratios, labels) {
  ratios$term <- factor(labels[ratios$term], levels = rev(labels[ratios$term]))
  ggplot2::ggplot(ratios, ggplot2::aes(hazard_ratio, term)) +
    ggplot2::geom_vline(xintercept = 1, linetype = "dashed", colour = muted) +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = lower, xmax = upper), width = 0, colour = muted, orientation = "y") +
    ggplot2::geom_point(colour = accent, size = 2) +
    ggplot2::scale_x_log10() +
    ggplot2::labs(x = "Hazard ratio (log scale; > 1 = buys again sooner)", y = NULL,
                  title = "Cox model: what predicts a faster second purchase (training customers)") +
    base_theme()
}
