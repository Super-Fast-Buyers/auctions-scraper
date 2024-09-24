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
        assessed_value,         # Include assessed value
        plaintiff_max_bid,      # Include plaintiff's max bid # nolint
        surplus_amount,
        case_number,            # Include case number
        parcel_id,              # Include parcel ID
        address = property_address,
        city,
        state,
        zip = zip_code        # Use the updated zip_code field
      )
  } else { # TAXDEED
    data <- data %>%
      select(
        auction_date,
        auction_time,           # Include auction time
        sold_to,                # Include buyer info
        sold_amount,            # Include sold amount
        opening_bid,
        assessed_value,         # Include assessed value
        opening_bid,
        surplus_amount,      # Include plaintiff's max bid
        case_number,
        certificate_number,            # Include case number
        parcel_id,              # Include parcel ID
        address = property_address,
        city,
        state,
        zip = zip_code         # Use the updated zip_code field
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
    file = sprintf("history/%s/auction_bid%s.csv", category, date_created),
    row.names = FALSE,
    na = ""
  )
}

#' Push Auction Data to Google Sheets
#' @param category category, foreclose or taxdeed
#'
push_auction <- function(category) {
  auction_data <- readRDS(paste0(category, ".rds"))
  # Rename columns based on category (foreclose or taxdeed)
  if (category == "foreclose") {
    names(auction_data) <- c(
        "Auction Type",
        "Auction Date",
        "Auction Time",           # Include auction time
        "Buyer",                # Include buyer info
        "Sold Amount",            # Include sold amount
        "Judgment Amount",
        "Assessed Value",         # Include assessed value
        "Plaintiff Max Bid",      # Include plaintiff's max bid # nolint
        "Surplus Amount",
        "Case No",            # Include case number
        "Parcel ID",              # Include parcel ID
        "Address",
        "City",
        "State",
        "ZIP",
        "Date Added"          # Added plaintiff max bid
    )
  } else { # taxdeed
    names(auction_data) <- c(
        "Auction Date",
        "Auction Time",           # Include auction time
        "Sold To",                # Include buyer info
        "Sold Amount",            # Include sold amount
        "Opening Bid",
        "Assessed Value",         # Include assessed value
        "Surplus Amount",      # Include plaintiff's max bid
        "Case No",
        "Certificate No",            # Include case number
        "Parcel ID",              # Include parcel ID
        "Address",
        "City",
        "State",
        "ZIP",
        "Date Added"         # Use the updated zip_code field
    )
  }

  # Authenticate with Google Sheets
  gs4_auth(path = Sys.getenv("CRED_PATH"))
  
  tryCatch({
    # Determine the sheet ID and the sheet tab name based on category
    sheet_id <- Sys.getenv(paste0("SHEETS_", toupper(category)))
    sheet_tab <- if (category == "foreclose") "3rd Bidders Foreclose" else "3rd Bidder Taxdeeds"
    
    # If the specific SHEETS environment variable is empty, fall back to the test sheet
    if (sheet_id == "") {
      sheet_write(auction_data, Sys.getenv("SHEETS_TEST"), sheet_tab)
    } else {
      sheet_write(auction_data, sheet_id, sheet_tab)
    }
    
    # Success message
    msg <- sprintf("%s data is now available on the '%s' tab in Google Sheets!", toupper(category), sheet_tab)
    message(msg)
    
  }, error = function(e) {
    # Error handling
    message("CANNOT send data to Google Sheets!")
  })
  
  # Deauthenticate
  gs4_deauth()
}