# Activate selenium docker container
system("docker run -d -p 4445:4444 selenium/standalone-chrome:latest")

# Loading generic functions
source("source.R")

# Selenium remote driver
remDr <- RSelenium::remoteDriver(
  remoteServerAddr = "localhost",
  port = 4445L,
  browserName = "chrome",
  extraCapabilities = list(
    chromeOptions = list(args = c(
      "--headless", 
      "--disable-gpu", 
      "--no-sandbox",
      # "--disable-extensions",
      "--disable-dev-shm-usage"))))
Sys.sleep(2)

# Listing domain and pages
subdomain <- read_delim("city.txt", "\n", col_names = FALSE, show_col_types = FALSE)[[1]]
domain_list <- sprintf("https://%s.realforeclose.com/index.cfm", subdomain)
calendar_list <- paste0(domain_list, "?zaction=USER&zmethod=CALENDAR")

# The days out
# 0 is today, + is num days of tomorrow, - num days of is yesterday
gs4_auth(path = Sys.getenv("CRED_PATH"))
days <- read_sheet(
  ss = Sys.getenv("SHEETS_ID"),
  sheet = "Schedule",
  range = "days_out",
  col_names = FALSE) %>%
  as.numeric()
gs4_deauth()

# Listing pages to be scraped
message("Constructing the list of pages")
longlist <- map(seq_along(calendar_list), ~{
  calendar_url <- paste0(calendar_list[[.x]], calendar_pages(days))
  i <- .x
  day_list <- map(calendar_url, ~{
    page <- scrape_page(.x)
    day_id <- sort(c(page %>% html_elements(".CALSELF") %>% html_attr("dayid"),
                     page %>% html_elements(".CALSELB") %>% html_attr("dayid")))
    day_list <- paste0(domain_list[[i]], "?zaction=AUCTION&Zmethod=PREVIEW&AUCTIONDATE=", day_id)
  })
  day_list <- do.call(c, day_list)
})
longls <- do.call(c, longlist)
longls <- longls[grepl("\\d{4}$", longls)]
# write_delim(data.frame(name = longls), "longlist.txt", delim = "\n", col_names = FALSE)
Sys.sleep(4)

# Scraping data
auction <- map(longls, ~{
  message(paste("Get", .x))
  page <- scrape_page(.x)
  np <- n_page(page)
  if (is.na(np)) np <- 1; message(paste0("Forced 1 page, np = ", np))
  if (np > 1) page <- scrape_pages(.x, np) else page <- list(page)
  if (str_detect(.x, "myorangeclerk")) auction <- parse_pages_case(page) else {
    auction <- parse_pages(page)
  }
  return(auction)
})
auction_data <- do.call(bind_rows, auction)

# Reshaping data
auction_data <- auction_data %>% 
  mutate(state = if_else(str_detect(zip, "^\\w+-\\s"), str_extract(zip, "^\\w+"), NA_character_),
         zip = if_else(str_detect(zip, "^\\w+-\\s"), str_remove(zip, "^\\w+-\\s"), zip),
         state = ifelse(is.na(state), "FL", state)) %>% 
  select(auction_date, judgment_amount, address, city, state, zip) %>% 
  arrange(auction_date, city, zip)

write_rds(auction_data, "auction.rds")
