# Pull Data from Website
pull_auction <- function(type) {
  
  # Listing domain and pages
  auction_category <- type
  subdomain <- read_delim(paste0(auction_category, ".txt"), "\n", 
                          col_names = FALSE, show_col_types = FALSE)[[1]]
  domain_list <- sprintf("https://%s.real%s.com/index.cfm", 
                         subdomain, 
                         auction_category)
  calendar_list <- paste0(domain_list, "?zaction=USER&zmethod=CALENDAR")
  
  # The days out
  # 0 is today, + is num days of tomorrow, - num days of is yesterday
  gs4_auth(path = Sys.getenv("CRED_PATH"))
  days <- tryCatch({
    read_sheet(
      ss = Sys.getenv(paste0("SHEETS_", toupper(auction_category))),
      sheet = "Schedule",
      range = "days_out",
      col_names = FALSE) %>%
      as.numeric()
  }, error = function(e) { 0 })
  gs4_deauth()
  
  # Listing pages to be scraped
  message("Constructing the list of pages")
  longlist <- map(seq_along(calendar_list), ~{
    calendar_url <- paste0(calendar_list[[.x]], calendar_pages(days))
    i <- .x
    day_list <- map(calendar_url, ~{
      page <- try(scrape_page(.x))
      Sys.sleep(0.5)
      if (auction_category == "foreclose") {
        day_id <- c(
          page %>% html_elements(".CALSELF") %>% html_attr("dayid"), 
          page %>% html_elements(".CALSELB") %>% html_attr("dayid")
        )
        auc_wait <- as.numeric(c(
          page %>% html_elements(".CALSELF") %>% html_elements(".CALACT") %>% html_text(),
          page %>% html_elements(".CALSELB") %>% html_elements(".CALACT") %>% html_text()
        ))
      } else {
        day_id <- page %>% 
          html_elements(".CALSELT") %>% 
          html_attr("dayid")
        auc_wait <- page %>% 
          html_elements(".CALSELT") %>% 
          html_elements(".CALACT") %>% 
          html_text() %>% 
          as.numeric()
      }
      day_id <- tibble(day_id, auc_wait) %>% 
        dplyr::filter(auc_wait > 0) %>% 
        arrange(day_id) %>% 
        .$day_id
      day_list <- paste0(domain_list[[i]], "?zaction=AUCTION&Zmethod=PREVIEW&AUCTIONDATE=", day_id)
      day_list <- day_list[grepl("\\d{4}$", day_list)]
      return(day_list)
    })
    day_list <- do.call(c, day_list)
  })
  longlist <- do.call(c, longlist)
  Sys.sleep(4)
  
  # Scraping data
  auction <- map(longlist, ~{
    message(paste("Get", .x))
    page <- try(scrape_page(.x))
    Sys.sleep(0.5)
    np <- n_page(page)
    if (is.na(np)) { np <- 1; message(paste0("Forced 1 page, np = ", np)) }
    if (np > 1) page <- scrape_pages(.x, np) else page <- list(page)
    if (str_detect(.x, "myorangeclerk")) auction <- parse_pages_case(page, auction_category) else {
      auction <- parse_pages(page, type = auction_category)
    }
    return(auction)
  })
  auction_data <- do.call(bind_rows, auction)
  
  auction_data <- auction_data %>% 
    mutate(state = if_else(str_detect(zip, "^\\w+-\\s"), str_extract(zip, "^\\w+"), NA_character_),
           zip = if_else(str_detect(zip, "^\\w+-\\s"), str_remove(zip, "^\\w+-\\s"), zip),
           state = ifelse(is.na(state), "FL", state),
           city = str_squish(city))
  
  # Reshaping previous data
  auction_past <- read_rds(paste0(auction_category, ".rds"))
  if (auction_category == "foreclose") {
    auction_past <- auction_past %>% 
      mutate(id = paste(address, city, state, zip, sep = ", "),
             .keep = "unused", .before = 1) %>% 
      select(-auction_date, -judgment_amount)
  } else { # taxdeed
    auction_past <- auction_past %>% 
      mutate(id = paste(address, city, state, zip, sep = ", "),
             .keep = "unused", .before = 1) %>% 
      select(-auction_date, -opening_bid)
  }
  
  # Creating data
  if (auction_category == "foreclose") {
    auction_data <- auction_data %>% 
      select(auction_date, judgment_amount, address, city, state, zip)
  } else { # taxdeed
    auction_data <- auction_data %>% 
      select(auction_date, opening_bid, address, city, state, zip)
  }
  auction_data <- auction_data %>% 
    arrange(auction_date, city, zip) %>% 
    mutate(id = paste(address, city, state, zip, sep = ", ")) %>% 
    left_join(auction_past, by = "id") %>% 
    select(-id) %>% 
    mutate(date_added = if_else(is.na(date_added),
                                format(Sys.Date(), "%m/%d/%Y"),
                                date_added)) %>% 
    distinct()
  
  # Filtering invalid city and address
  invalid_addr <- c("NO SITUS", "NO STREET", "UNKNOWN", "NOT ASSIGNED", "UNASSIGNED")
  auction_data <- auction_data %>% 
    dplyr::filter(!(is.na(city) | address %in% invalid_addr))
  
  # Save data
  write_rds(auction_data, paste0(auction_category, ".rds"))
  write_csv(auction_data, 
            paste0(sprintf("history/%s/auction_", auction_category), 
                   Sys.Date(), 
                   ".csv"))
  message(sprintf("Data was saved to 'history/%s'", auction_category))
  
  return(message("Done"))
  
}


# Push data to Google Sheets
push_auction <- function(type) {
  
  auctype <- type
  auction_data <- readRDS(paste0(auctype, ".rds"))
  if (type == "foreclose") {
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
    sheet_write(auction_data, Sys.getenv(paste0("SHEETS_", toupper(auctype))), "Raw")
    # sheet_write(auction_data, Sys.getenv("SHEETS_TEST"), "Raw")
    message("Data is now available on Google Sheets!")
  }, error = function(e) message("CANNOT send data to Google Sheets!"))
  gs4_deauth()
  
}
