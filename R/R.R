library(dplyr, warn.conflicts = FALSE)
library(googlesheets4)
library(jsonlite)

#' Import New Auction Data from JSON
#' @param json json file
#' @param category category, FORECLOSURE or TAXDEED
#' 
json2tbl <- function(json, category) {
  if (!(category %in% c("FORECLOSURE", "TAXDEED"))) {
    stop("Argument 'category' must be FORECLOSURE or TAXDEED")
  }
  data <- fromJSON(suppressWarnings(readLines(json))) %>% 
    dplyr::filter(
      auction_type == category,
      !is.na(auction_date),
      !is.na(property_address)
    ) %>% 
    as_tibble()
  if (category == "FORECLOSURE") {
    data <- data %>% 
      select(
        auction_date,
        judgment_amount = final_judgment_amount,
        address = property_address,
        city,
        state,
        zip = zip
      )
  } else { # TAXDEED
    data <- data %>% 
      select(
        auction_date,
        opening_bid,
        address = property_address,
        city,
        state,
        zip = zip
      )
  }
  # filter invalid location data
  invalid_addr <- c("UNKNOWN", "NOT ASSIGNED", "UNASSIGNED")
  data <- data %>% 
    dplyr::filter(
      !(is.na(city) | 
          grepl(pattern = "^NO\\s", x = .$address) | 
          address %in% invalid_addr)
    )
  return(data)
}

#' Combine Old Auction Data with the Newest
#' @param old_data_rds old rds file
#' @param new_data new imported data from json
#' 
combine_data <- function(old_data_rds, new_data) {
  # reshape old data
  auction_past <- readRDS(old_data_rds) %>% 
    mutate(id = paste(address, city, state, zip, sep = ", "),
           .keep = "unused", .before = 1) %>% 
    select(id, date_added) %>%
    distinct()
  # combine old data with the newest data
  auction_data <- new_data %>% 
    mutate(id = paste(address, city, state, zip, sep = ", ")) %>% 
    left_join(auction_past, by = "id") %>% 
    select(-id) %>% 
    mutate(
      date_added = ifelse(
        is.na(date_added),
        format(Sys.Date(), "%m/%d/%Y"),
        date_added),
      auction_date = as.Date(auction_date, "%m/%d/%Y")
    ) %>% 
    arrange(auction_date, city, zip) %>% 
    mutate(auction_date = format(auction_date, "%m/%d/%Y")) %>% 
    distinct()
  return(auction_data)
}

#' Save New Combined Auction Data to CSV for History
#' @param new_data new imported data from json
#' @param category category, foreclose or taxdeed
#' 
save_auction_csv <- function(new_data, category) {
  if (!(category %in% c("foreclose", "taxdeed"))) {
    stop("Argument 'category' must foreclose or taxdeed")
  }
  date_created <- format(Sys.Date(), "%Y-%m-%d")
  write.csv(
    x = new_data,
    file = sprintf("history/%s/auction_%s.csv", category, date_created),
    row.names = FALSE,
    na = ""
  )
}

#' Push Auction Data to Google Sheets
#' @param category category, foreclose or taxdeed
#' 
push_auction <- function(category) {
  auction_data <- readRDS(paste0(category, ".rds"))
  if (category == "foreclose") {
    names(auction_data) <- c(
      "Auction Date", 
      "Judgment Amount", 
      "Address", "City", 
      "State", 
      "Zip",
      "Date Added"
    )
  } else { # taxdeed
    names(auction_data) <- c(
      "Auction Date", 
      "Opening Bid", 
      "Address", "City", 
      "State", 
      "Zip",
      "Date Added"
    )
  }
  gs4_auth(path = Sys.getenv("CRED_PATH"))
  tryCatch({
    if (Sys.getenv(paste0("SHEETS_", toupper(category))) == "") {
      sheet_write(auction_data, Sys.getenv("SHEETS_TEST"), "Raw")
    }
    else {
      sheet_write(auction_data, Sys.getenv(paste0("SHEETS_", toupper(category))), "Raw")
    }
    # sheet_write(auction_data, Sys.getenv(paste0("SHEETS_", toupper(category))), "Raw")
    # sheet_write(auction_data, Sys.getenv("SHEETS_TEST"), "Raw")
    msg <- sprintf("%s data is now available on Google Sheets!", toupper(category))
    message(msg)
  }, error = function(e) message("CANNOT send data to Google Sheets!"))
  gs4_deauth()
}
