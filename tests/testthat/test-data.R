sheet <- function(invoice, date, quantity = 1) {
  tibble::tibble(Invoice = invoice, StockCode = "22423", Quantity = quantity,
                 InvoiceDate = as.POSIXct(date, tz = "UTC"), Price = 1)
}

test_that("an identical sheet overlap is removed exactly once", {
  first <- sheet(c("1", "2"), c("2010-11-30", "2010-12-02"))
  second <- sheet(c("2", "3"), c("2010-12-02", "2010-12-20"))
  combined <- combine_sheets(first, second)
  expect_equal(combined$overlap_rows_removed, 1)
  expect_equal(combined$lines$Invoice, c("1", "2", "3"))
})

test_that("a mismatched overlap is refused rather than guessed", {
  first <- sheet("2", "2010-12-02")
  second <- sheet("2", "2010-12-02", quantity = 9)
  expect_error(combine_sheets(first, second), "not an exact duplicate")
})

test_that("only identified merchandise sales are kept", {
  lines <- tibble::tibble(
    invoice = c("1", "C2", "3", "4", "5", "6", "7"),
    stock_code = c("85123A", "22423", "POST", "22423", "22423", "15056bl", "22423"),
    quantity = c(1, -1, 1, 0, 1, 2, 1),
    price = c(2, 2, 2, 2, 0, 3, 2),
    customer_id = c(1, 1, 1, 1, 1, 1, NA),
    invoice_date = as.POSIXct("2011-01-05 10:00", tz = "UTC"),
    country = "United Kingdom"
  )
  kept <- customer_sales(lines)
  expect_equal(kept$invoice, c("1", "6"))           # cancellation, postage, zero qty/price, anonymous removed
  expect_equal(kept$line_value, c(2, 6))
})

test_that("a tampered workbook fails the checksum", {
  path <- tempfile(fileext = ".xlsx")
  writeLines("not the workbook", path)
  expect_error(verify_file(path, workbook_sha256), "checksum mismatch")
})
