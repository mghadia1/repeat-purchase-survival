# How it works

```
UCI zip ─▶ online_retail_II.xlsx (SHA-256, digest) ─▶ readxl, 2 sheets ─▶ combine_sheets (overlap proven identical, removed)
      ─▶ customer_sales (cleaning rules, dplyr) ─▶ build_customers (one row per customer: time, returned, first-order features)
      ─▶ survival: survfit (Kaplan–Meier), survdiff (log-rank), coxph + cox.zph, concordance, calibration
      ─▶ ggplot2 figures, CSVs, summary.json (jsonlite)
```

## Layout

| Path | Contents |
|---|---|
| `R/data.R` | download, checksum, sheet-overlap fix, cleaning rules |
| `R/survival_data.R` | customer table (time, event, censoring, left-censoring guard); naive rates for comparison |
| `R/analysis.R` | Kaplan–Meier helpers, group curves and log-rank, Cox fit, proportional-hazards check, held-out concordance, calibration |
| `R/plots.R` | ggplot2 figures |
| `scripts/run.R` | `download` and `analyze` commands |
| `tests/testthat/` | 12 tests |
| `renv.lock` | exact package versions, restored with `renv::restore()` |

## Key terms, in one line each

- **Censored:** we know the customer had not returned *by* the time the data ends, not that they never will.
- **Kaplan–Meier:** estimates P(still not returned by day t) by multiplying, day by day, the share of customers *still being watched* who did not return that day. A censored customer counts until the day they leave the data.
- **Log-rank test:** are two or more survival curves different? It is most powerful when one group is consistently ahead, and weak when curves cross.
- **Cox model:** hazard(t | x) = baseline(t) × exp(β·x). It estimates how factors multiply the "instantaneous rate of returning" without assuming the baseline's shape.
- **Proportional hazards:** the Cox assumption that exp(β) is the same at day 10 and day 300. `cox.zph` tests it with Schoenfeld residuals.
- **Harrell's C:** among pairs of customers where we can tell who returned first, the share the model orders correctly. 0.5 is chance.

## Choices I would defend

| Choice | Why |
|---|---|
| Survival analysis, not "% returned within N days" | Recent customers are censored, not lost. Section 2 of the results measures the naive rate at 7 points low over one year |
| A return is a purchase on a **later day** | Same-day second invoices are mostly split or corrected orders |
| Exclude customers first seen before 1 Mar 2010 | Some of them are old customers whose history was cut off. The sensitivity table shows the cutoff is enough |
| Log-transform value and item count | Both are heavily skewed. A hazard ratio "per 2.7×" is stable, where one "per £1" is meaningless |
| Check proportional hazards and act on it | The season ratio (0.90) would be misleading; the curves and the stratified model are reported instead |
| Split by customer, 70/30, and evaluate once | The same idea as the Python projects: no customer is in both training and test |
| renv lockfile | Anyone gets the same package versions. Homebrew's R builds packages from source, so pinned versions matter |

## Tests (12)

**Data:**
- sheet-overlap removal, and refusal when the overlap doesn't match;
- the cleaning rules;
- checksum rejection.

**Survival table:**
- time, event, and first-order features on hand-built customers: a return after 10 days; a same-day second invoice that must not count; a customer first seen before the guard; a customer first seen on the last day;
- the naive-rate arithmetic, including a case that the first, outcome-dependent rule would get wrong.

**Methods, on simulated data with a known truth:**
- with no censoring, Kaplan–Meier equals the plain proportion;
- Kaplan–Meier recovers the true 180-day rate while the naive rate is more than 10 points low, and the fixed follow-up subset is unbiased when early and late customers are alike;
- Cox recovers a hazard ratio of 2;
- `cox.zph` flags crossing hazards and passes parallel ones;
- held-out C is about 0.5 for a noise variable and above 0.6 for a real one;
- a correct model's calibration deciles are within 8 points.

## Things to be able to explain

- What is censoring, and why is "% returned within a year" biased? Why is dropping recent customers only fair if they behave like early ones?
- What was wrong with the first "enough follow-up" rule, and why does choosing customers by their outcome bias a rate?
- How does Kaplan–Meier use a customer who was observed for only 40 days?
- What does a hazard ratio of 1.14 per 2.7× first-order value mean in plain words?
- Why is the season hazard ratio not reported as a finding? What do crossing curves mean?
- Why is a C of 0.58 honest, and what data would raise it?
