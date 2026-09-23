# Turn transactions into one row per customer: time from first purchase to the
# next purchase on a later day, or censoring at the end of the data.
#
# Why survival analysis and not "% who came back within N days":
# a customer first seen three weeks before the data ends has had three weeks to
# come back. Counting them as "did not return within 180 days" is wrong - we
# do not know yet. Survival methods treat them as censored at three weeks and
# use exactly the information they carry.

build_customers <- function(sales, data_end, first_seen_from) {
  first_orders <- sales |>
    dplyr::group_by(customer_id) |>
    dplyr::mutate(first_day = min(day)) |>
    dplyr::ungroup()

  first_basket <- first_orders |>
    dplyr::filter(day == first_day) |>
    dplyr::group_by(customer_id, first_day) |>
    dplyr::summarise(
      first_value = sum(line_value),
      first_items = dplyr::n_distinct(stock_code),
      first_invoices = dplyr::n_distinct(invoice),
      country = dplyr::first(country),
      .groups = "drop"
    )

  # "Buying again" means an order on a LATER day: a second invoice on the same
  # day is usually a split or corrected order, not a return visit.
  next_day <- first_orders |>
    dplyr::filter(day > first_day) |>
    dplyr::group_by(customer_id) |>
    dplyr::summarise(next_day = min(day), .groups = "drop")

  first_basket |>
    dplyr::left_join(next_day, by = "customer_id") |>
    dplyr::mutate(
      returned = as.integer(!is.na(next_day)),
      time = as.numeric(ifelse(returned == 1, next_day - first_day, data_end - first_day)),
      # how long the customer COULD have been watched, whatever happened: the
      # basis for a fair "enough follow-up" subset (unlike `time`, it does not
      # depend on whether or when they returned)
      follow_up = as.numeric(data_end - first_day),
      uk = as.integer(country == "United Kingdom"),
      holiday_season = as.integer(as.integer(format(first_day, "%m")) %in% 9:11),
      log_first_value = log(first_value),
      log_first_items = log(first_items)
    ) |>
    # Left censoring: the data starts 2009-12-01, so a customer "first seen" in
    # the first months may be a long-time customer whose earlier orders are
    # missing. Their first purchase in the data is not their first purchase.
    dplyr::filter(first_day >= first_seen_from) |>
    # A customer first seen on the final day has zero follow-up and adds nothing.
    dplyr::filter(time > 0)
}

# The naive estimate, done two ways, to show what censoring does to it.
#
# The first version of `enough_follow_up` kept every customer whose outcome at
# the horizon was *known* - which includes recent customers who happened to
# return quickly and drops recent ones who had not yet. Choosing whom to count
# by their outcome biased it upward (74.1% vs Kaplan-Meier's 67.8% at a year).
# The correct subset depends only on when the customer arrived.
naive_return_rate <- function(customers, horizon) {
  within <- customers$returned == 1 & customers$time <= horizon
  long_enough <- customers$follow_up >= horizon
  c(
    all_customers = mean(within),                 # treats "not yet" as "never": biased low
    enough_follow_up = mean(within[long_enough])  # drops recent customers: wasteful, and unbiased
  )                                               # only if early and late customers behave alike
}
