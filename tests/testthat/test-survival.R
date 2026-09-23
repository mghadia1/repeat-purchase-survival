sale <- function(customer, day, invoice, value = 10, country = "United Kingdom", item = "22423") {
  tibble::tibble(customer_id = customer, day = as.Date(day), invoice = invoice, stock_code = item,
                 line_value = value, country = country)
}

fixture <- function() {
  dplyr::bind_rows(
    sale(1, "2010-05-01", "a", 20), sale(1, "2010-05-01", "a", 30, item = "85123A"),  # 2 items, value 50
    sale(1, "2010-05-11", "b"),                                                    # back 10 days later
    sale(2, "2010-06-01", "c"), sale(2, "2010-06-01", "d"),                          # same-day second invoice only
    sale(3, "2010-01-15", "e"), sale(3, "2010-02-01", "f"),                          # first seen before the guard
    sale(4, "2010-12-31", "g", country = "France")                                  # first seen on the last day
  )
}

test_that("customer rows carry the right time, event, and first-order features", {
  customers <- build_customers(fixture(), as.Date("2010-12-31"), as.Date("2010-03-01"))
  expect_equal(sort(customers$customer_id), c(1, 2))           # 3 is left-censored, 4 has no follow-up
  one <- customers[customers$customer_id == 1, ]
  two <- customers[customers$customer_id == 2, ]
  expect_equal(c(one$returned, one$time, one$first_value, one$first_items), c(1, 10, 50, 2))
  expect_equal(c(two$returned, two$time), c(0, 213))           # censored at the data end, 1 Jun -> 31 Dec
  expect_equal(one$follow_up, 244)                             # could have been watched 1 May -> 31 Dec
  expect_equal(two$first_invoices, 2)
})

test_that("naive rates count 'not yet' two different ways", {
  customers <- data.frame(returned = c(1, 1, 0, 0, 1),
                          time = c(10, 200, 300, 50, 20),
                          follow_up = c(400, 400, 300, 50, 60))
  rates <- naive_return_rate(customers, 90)
  expect_equal(unname(rates["all_customers"]), 2 / 5)
  # customers 4 and 5 arrived too late to be watched for 90 days, so both are
  # dropped - including customer 5, who returned. Keeping them only when they
  # returned (the first version) would give 2 / 4 and bias the rate upward.
  expect_equal(unname(rates["enough_follow_up"]), 1 / 3)
})

test_that("with no censoring, Kaplan-Meier equals the plain proportion", {
  customers <- data.frame(time = c(5, 10, 20, 40), returned = 1)
  fit <- survival::survfit(survival::Surv(time, returned) ~ 1, data = customers)
  expect_equal(km_at(fit, c(10, 30))$returned, c(0.5, 0.75))
  expect_equal(km_median(fit), 15)
})

simulate <- function(n = 6000, seed = 1, hr = 1, crossing = FALSE) {
  set.seed(seed)
  x <- rbinom(n, 1, 0.5)
  rate <- 1 / 100 * ifelse(x == 1, hr, 1)
  time <- rexp(n, rate)
  if (crossing) {
    # group 1: fast early returns, then almost none - hazards cross
    late <- x == 1 & runif(n) < 0.5
    time[x == 1] <- ifelse(late[x == 1], rexp(sum(x == 1), 1 / 600), rexp(sum(x == 1), 1 / 20))
  }
  follow_up <- runif(n, 0, 500)                       # staggered entry: some customers are recent
  data.frame(x = x, time = pmax(pmin(time, follow_up), 0.5), returned = as.integer(time <= follow_up),
             follow_up = follow_up)
}

test_that("Kaplan-Meier recovers the truth where the naive rate does not", {
  customers <- simulate()
  truth <- 1 - exp(-180 / 100)
  bias <- censoring_bias(customers, horizons = 180)
  expect_lt(abs(bias$kaplan_meier - truth), 0.03)
  expect_gt(truth - bias$naive_all, 0.10)            # 'not yet' counted as 'never'
  # with identical early and late customers, the fair subset is unbiased too
  expect_lt(abs(bias$naive_enough_follow_up - truth), 0.03)
})

test_that("the Cox model recovers a known hazard ratio", {
  customers <- simulate(hr = 2, seed = 2)
  model <- survival::coxph(survival::Surv(time, returned) ~ x, data = customers)
  expect_equal(unname(exp(coef(model))), 2, tolerance = 0.1)
})

test_that("the proportional-hazards check flags crossing curves and passes parallel ones", {
  parallel <- survival::coxph(survival::Surv(time, returned) ~ x, data = simulate(hr = 1.5, seed = 3))
  crossing <- survival::coxph(survival::Surv(time, returned) ~ x, data = simulate(crossing = TRUE, seed = 3))
  expect_gt(ph_check(parallel)$p[1], 0.01)
  expect_lt(ph_check(crossing)$p[1], 0.001)
})

test_that("held-out concordance is about 0.5 for noise and higher for a real signal", {
  customers <- simulate(hr = 3, seed = 4)
  customers$noise <- rnorm(nrow(customers))
  parts <- split_customers(customers)
  signal <- held_out_concordance(fit_cox(parts$train, survival::Surv(time, returned) ~ x), parts$test)
  noise <- held_out_concordance(fit_cox(parts$train, survival::Surv(time, returned) ~ noise), parts$test)
  expect_gt(signal[["c_index"]], 0.6)
  expect_lt(abs(noise[["c_index"]] - 0.5), 0.03)
})

test_that("calibration returns one row per decile, and a correct model is calibrated", {
  customers <- simulate(hr = 2, seed = 5)
  parts <- split_customers(customers)
  model <- fit_cox(parts$train, survival::Surv(time, returned) ~ x)
  calibration <- calibration_at(model, parts$test, 90, groups = 10)
  expect_equal(nrow(calibration), 10)
  expect_equal(sum(calibration$n), nrow(parts$test))
  expect_lt(max(abs(calibration$predicted - calibration$observed)), 0.08)
})
