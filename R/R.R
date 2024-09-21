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
        auction_type,
        auction_date,
        auction_time,           # Include auction time
        sold_to,                # Include buyer info
        sold_amount,            # Include sold amount
        judgment_amount = final_judgment_amount,
        case_number,            # Include case number
        parcel_id,              # Include parcel ID
        address = property_address,
        city,
        state,
        zip = zip_code,         # Use the updated zip_code field
        assessed_value,         # Include assessed value
        plaintiff_max_bid,      # Include plaintiff's max bid # nolint
        surplus_amount
      )
  } else { # TAXDEED
    data <- data %>%
      select(
        auction_date,
        auction_time,           # Include auction time
        sold_to,                # Include buyer info
        sold_amount,            # Include sold amount
        opening_bid,
        case_number,
        certificate_number,            # Include case number
        parcel_id,              # Include parcel ID
        address = property_address,
        city,
        state,
        zip = zip_code,         # Use the updated zip_code field
        assessed_value,         # Include assessed value
        opening_bid,
        surplus_amount      # Include plaintiff's max bid
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
  # Check if the old_data_rds file exists
  if (file.exists(old_data_rds)) {
    # Reshape old data
    auction_past <- readRDS(old_data_rds) %>%
      mutate(id = paste(address, city, state, zip, sep = ", "),
             .keep = "unused", .before = 1) %>%
      select(id, date_added) %>%
      distinct()

    # Combine old data with the newest data
    auction_data <- new_data %>%
      mutate(id = paste(address, city, state, zip, sep = ", ")) %>% 
      left_join(auction_past, by = "id") %>%
      select(-id) %>%
      mutate(
        date_added = ifelse(
          is.na(date_added),
          format(Sys.Date(), "%m/%d/%Y"),
          date_added
        ),
        auction_date = as.Date(auction_date, "%m/%d/%Y")
      ) %>%
      arrange(auction_date, city, zip) %>%
      mutate(auction_date = format(auction_date, "%m/%d/%Y")) %>%
      distinct()

  } else {
    # If the old_data_rds doesn't exist, just return the new_data
    auction_data <- new_data %>%
      mutate(
        auction_date = as.Date(auction_date, "%m/%d/%Y"),
        date_added = format(Sys.Date(), "%m/%d/%Y")
      ) %>% 
      arrange(auction_date, city, zip) %>% 
      mutate(auction_date = format(auction_date, "%m/%d/%Y")) %>%
      distinct()
  }

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
      "Date Added",
      "Auction Date",
      "Auction Time",
      "Auction Type",        # Added auction time
      "Sold To",
      "Assessed Value",      # Added assessed_value
      "Plaintiff Max Bid",            # Added sold_to
      "Sold Amount",         # Added sold_amount
      "Judgment Amount",
      "Surplus Amount",
      "Case Number",         # Added case number
      "Parcel ID",           # Added parcel_id
      "Address",
      "City",
      "State",
      "Zip",   # Added plaintiff max bid
    )
  }else{ # taxdeed
    names(auction_data) <- c(
       "Date Added",
      "Auction Date",
      "Auction Time",
      "Auction Type",      # Added auction time
      "Sold To",
      "Assessed Value",      # Added assessed_value             # Added sold_to
      "Sold Amount",         # Added sold_amount
      "Opening Bid",
      "Surplus Amount",
      "Case Number",
      "Certificate Number",        # Added case number
      "Parcel ID",           # Added parcel_id
      "Address",
      "City",
      "State",
      "Zip",
    )
  }

  gs4_auth(path = Sys.getenv("CRED_PATH"))
  tryCatch({
    if (Sys.getenv(paste0("SHEETS_", toupper(category))) == "") {
      sheet_write(auction_data, Sys.getenv("SHEETS_TEST"), "Raw")
    }else {
      sheet_write(auction_data, Sys.getenv(paste0("SHEETS_", toupper(category))), "Raw")
    }
    msg <- sprintf("%s data is now available on Google Sheets!", toupper(category))
    message(msg)
  }, error = function(e) message("CANNOT send data to Google Sheets!"))
  gs4_deauth()
}