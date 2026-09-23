# Download, verify, and clean the UCI Online Retail II workbook.
#
# The cleaning rules match the Python retail-cohort-analytics project on
# purpose: the same "sale" definition, so results can be compared across the
# two projects. They are re-implemented here in R, not imported.

dataset_url <- "https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip"
workbook_name <- "online_retail_II.xlsx"
# SHA-256 of the extracted workbook, recorded 2026-09-22.
workbook_sha256 <- "bcbe73b35f5b7babf197fb0cb983a11f5d9ff929078d4aa53d171b1f2df2e980"

overlap_start <- as.POSIXct("2010-12-01", tz = "UTC")
key_columns <- c("Invoice", "StockCode", "Quantity", "InvoiceDate", "Price")

sha256_of <- function(path) digest::digest(file = path, algo = "sha256")

verify_file <- function(path, expected) {
  actual <- sha256_of(path)
  if (!identical(actual, expected)) stop(sprintf("checksum mismatch for %s: %s", basename(path), actual))
  invisible(path)
}

download_workbook <- function(destination = "data/raw") {
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  workbook <- file.path(destination, workbook_name)
  if (!file.exists(workbook)) {
    archive <- file.path(destination, "online_retail_ii.zip")
    utils::download.file(dataset_url, archive, mode = "wb", quiet = TRUE)
    utils::unzip(archive, files = workbook_name, exdir = destination)
    unlink(archive)
  }
  verify_file(workbook, workbook_sha256)
}

read_sheet <- function(workbook, sheet) {
  # Text columns forced to text: some descriptions and stock codes look numeric.
  readxl::read_excel(
    workbook, sheet = sheet,
    col_types = c("text", "text", "text", "numeric", "date", "numeric", "numeric", "text")
  )
}

# Stack the two yearly sheets, dropping the duplicated 1-9 Dec 2010 window once.
# Stops if the overlap is not an exact copy, rather than guessing which to keep.
combine_sheets <- function(first, second) {
  overlap_end <- max(first$InvoiceDate)
  first_window <- first[first$InvoiceDate >= overlap_start, key_columns]
  second_window <- second[second$InvoiceDate <= overlap_end, key_columns]
  canonical <- function(frame) {
    frame <- as.data.frame(frame)
    frame[do.call(order, unname(as.list(frame))), , drop = FALSE] |> `rownames<-`(NULL)
  }
  if (!isTRUE(all.equal(canonical(first_window), canonical(second_window), check.attributes = FALSE))) {
    stop("sheet overlap window is not an exact duplicate; refusing to drop it")
  }
  list(
    lines = dplyr::bind_rows(first[first$InvoiceDate < overlap_start, ], second),
    overlap_rows_removed = nrow(first_window)
  )
}

load_lines <- function(workbook) {
  sheets <- readxl::excel_sheets(workbook)
  if (length(sheets) != 2) stop(sprintf("expected 2 sheets, found %d", length(sheets)))
  combined <- combine_sheets(read_sheet(workbook, sheets[1]), read_sheet(workbook, sheets[2]))
  combined$lines <- dplyr::rename(
    combined$lines,
    invoice = Invoice, stock_code = StockCode, description = Description, quantity = Quantity,
    invoice_date = InvoiceDate, price = Price, customer_id = `Customer ID`, country = Country
  )
  combined
}

# A sale: merchandise (five-digit stock code, optional letters), not a
# cancellation, positive quantity and price, and an identified customer -
# survival analysis follows customers, so anonymous lines cannot be used.
customer_sales <- function(lines) {
  lines |>
    dplyr::filter(
      grepl("^[0-9]{5}[A-Za-z]*$", stock_code),
      !startsWith(invoice, "C"),
      quantity > 0, price > 0,
      !is.na(customer_id)
    ) |>
    dplyr::mutate(line_value = quantity * price, day = as.Date(invoice_date))
}
