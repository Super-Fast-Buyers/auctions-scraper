library(tidyverse)
library(rvest)
library(lubridate)
library(googlesheets4)

# function for scraping single page
scrape_page <- function(url) {
  remDr$open(silent = TRUE)
  remDr$navigate(url)
  Sys.sleep(1)
  pgSrc <- remDr$getPageSource()
  page <- try(read_html(pgSrc[[1]]))
  remDr$close()
  return(page)
}

# function for scraping page with next button
scrape_pages <- function(url, n_page) {
  remDr$open(silent = TRUE)
  page <- map(1:n_page, ~{
    remDr$navigate(url)
    Sys.sleep(1)
    i <- 1
    while (i < .x) {
      remDr$findElement("xpath", '//*[@id="BID_WINDOW_CONTAINER"]/div[3]/div[3]/span[3]')$clickElement()
      Sys.sleep(3)
      i <- i + 1
    }
    pgSrc <- remDr$getPageSource()
    page <- try(read_html(pgSrc[[1]]))
  })
  remDr$close()
  return(page)
}

# function for get calendar pages to be scraped
calendar_pages <- function(days) {
  if (missing(days)) days <- 0
  tday <- today() + days
  days_out <- tday + 90
  cal_pages <- c(seq(tday, days_out, by = 28), days_out)
  cal_pages <- cal_pages[!duplicated(month(cal_pages))]
  cal_pages <-  paste0("&selCalDate=", format(cal_pages, "%m/%d/%Y"))
  return(cal_pages)
}

# function for get number of next page button
n_page <- function(page) {
  n_page <- page %>% 
    html_elements(".Head_W") %>% 
    html_element(".PageText") %>% 
    html_element("span") %>% 
    html_text() %>% 
    as.numeric()
  return(n_page)
}

# function for scrape monthly auction data
parse_monthly <- function(day_list) {
  auction_data <- map(day_list, ~{
    page <- scrape_page(.x)
    # parsing table
    tbl_data <- page %>% 
      html_element(".Head_W") %>% 
      html_elements(".Auct_Area") %>% 
      html_elements(".AUCTION_ITEM") %>% 
      html_table()
    # auction waiting
    if (length(tbl_data) == 0) {
      auction_data <- NULL
    } else {
      df_tbl <- map_df(tbl_data, ~{
        .x %>% 
          mutate(X1 = if_else(X1 == "", "city", X1)) %>% 
          pivot_wider(names_from = "X1", values_from = "X2", values_fill = "X") %>% 
          janitor::clean_names()
      })
      auction_date <- page %>% 
        html_element(".Head_W") %>% 
        html_elements(".Auct_Area") %>% 
        html_elements(".AUCTION_STATS") %>% 
        html_element(".Astat_DATA") %>% 
        html_text()
      df_tbl <- bind_cols(df_tbl, auction_date = auction_date)
      # address checking
      if (is.null(suppressWarnings(df_tbl$property_address))) {
        auction_data <- NULL
      } else {
        auction_data <- df_tbl %>% 
          dplyr::filter(!is.na(property_address)) %>% 
          dplyr::filter(auction_type == "FORECLOSURE") %>% 
          select(auction_date, final_judgment_amount, property_address, city) %>% 
          separate(city, into = c("city", "state"), sep = ", ") %>% 
          separate(state, into = c("state", "zip"), sep = "- ") %>% 
          mutate(auction_date = if_else(str_detect(auction_date, "^(\\d{2}/){2}\\d{4}"),
                                        str_extract(auction_date, "^(\\d{2}/){2}\\d{4}"),
                                        auction_date)) %>% 
          rename(judgment_amount = final_judgment_amount,
                 address = property_address)
      } # end of address checking
    } # end of auction waiting
    auction_data
  })
  auction_data <- do.call(bind_rows, auction_data)
  # if ((class(auction_data)=="tbl_df")&&(length(auction_data)==0)) {
  #   auction_data <- NULL
  # }
  return(auction_data)
}

# function for parsing page without next
parse_page <- function(page) {
  # parsing table
  tbl_data <- page %>% 
    html_element(".Head_W") %>% 
    html_elements(".Auct_Area") %>% 
    html_elements(".AUCTION_ITEM") %>% 
    html_table()
  # auction waiting
  if (length(tbl_data) == 0) {
    auction_data <- NULL
  } else {
    df_tbl <- map_df(tbl_data, ~{
      .x %>% 
        mutate(X1 = if_else(X1 == "", "city", X1)) %>% 
        pivot_wider(names_from = "X1", values_from = "X2", values_fill = "X") %>% 
        janitor::clean_names()
    })
    auction_date <- page %>% 
      html_element(".Head_W") %>% 
      html_elements(".Auct_Area") %>% 
      html_elements(".AUCTION_STATS") %>% 
      html_element(".Astat_DATA") %>% 
      html_text()
    df_tbl <- bind_cols(df_tbl, auction_date = auction_date)
    # address checking
    if (is.null(suppressWarnings(df_tbl$property_address))) {
      auction_data <- NULL
    } else {
      auction_data <- df_tbl %>% 
        dplyr::filter(!is.na(property_address)) %>% 
        dplyr::filter(auction_type == "FORECLOSURE") %>% 
        select(auction_date, final_judgment_amount, property_address, city) %>% 
        separate(city, into = c("city", "zip"), sep = ", ") %>% 
        mutate(auction_date = if_else(str_detect(auction_date, "^(\\d{2}/){2}\\d{4}"),
                                      str_extract(auction_date, "^(\\d{2}/){2}\\d{4}"),
                                      auction_date)) %>% 
        rename(judgment_amount = final_judgment_amount,
               address = property_address)
    } # end of address checking
  } # end of auction waiting
  return(auction_data)
}

# function for parsing page in list
parse_pages <- function(page) {
  auction_data <- map(page, ~{
    # parsing table
    tbl_data <- .x %>% 
      html_element(".Head_W") %>% 
      html_elements(".Auct_Area") %>% 
      html_elements(".AUCTION_ITEM") %>% 
      html_table()
    # auction waiting
    if (length(tbl_data) == 0) {
      auction_data <- NULL
    } else if (length(tbl_data) != 0 & (map_dbl(tbl_data, ~{nrow(.x)}) %>% sum()) == 0) {
      auction_data <- NULL
    } else {
      df_tbl <- map_df(tbl_data, ~{
        .x %>% 
          mutate(X1 = if_else(X1 == "", "city", X1)) %>% 
          pivot_wider(names_from = "X1", values_from = "X2", values_fill = "X") %>% 
          janitor::clean_names()
      })
      auction_date <- .x %>% 
        html_element(".Head_W") %>% 
        html_elements(".Auct_Area") %>% 
        html_elements(".AUCTION_STATS") %>% 
        html_element(".Astat_DATA") %>% 
        html_text()
      df_tbl <- bind_cols(df_tbl, auction_date = auction_date)
      # address checking
      if (is.null(suppressWarnings(df_tbl$property_address))) {
        auction_data <- NULL
      } else {
        auction_data <- df_tbl %>% 
          dplyr::filter(!is.na(property_address)) %>% 
          dplyr::filter(auction_type == "FORECLOSURE") %>% 
          select(auction_date, final_judgment_amount, property_address, city) %>% 
          separate(city, into = c("city", "zip"), sep = ", ") %>% 
          mutate(auction_date = if_else(str_detect(auction_date, "^(\\d{2}/){2}\\d{4}"),
                                        str_extract(auction_date, "^(\\d{2}/){2}\\d{4}"),
                                        auction_date)) %>% 
          rename(judgment_amount = final_judgment_amount,
                 address = property_address)
      } # end of address checking
    } # end of auction waiting
    auction_data
  }) # end of map iteration
  auction_data <- do.call(bind_rows, auction_data)
  return(auction_data)
}

# function for parsing page in list with conditional case, keyword: myorangeclerk
parse_pages_case <- function(page) {
  auction_data <- map(page, ~{
    # parsing table
    tbl_data <- .x %>%
      html_element(".Head_W") %>% 
      html_elements(".Auct_Area") %>% 
      html_elements(".AUCTION_ITEM")
    # auction waiting
    if (length(tbl_data) == 0) {
      auction_data <- NULL
    } else {
      tbl_header <- map(tbl_data, ~{
        .x %>% 
          html_elements(".AD_LBL") %>% 
          html_text() %>% 
          janitor::make_clean_names()
      })
      tbl_detail <- map(tbl_data, ~{
        .x %>% 
          html_elements(".AD_DTA") %>% 
          html_text() %>% 
          str_squish()
      })
      df_tbl <- map2_df(tbl_detail, tbl_header, ~{
        tibble(names = .y, values = .x) %>% 
          pivot_wider(names_from = "names", values_from = "values")
      })
      auction_date <- tbl_data %>%
        html_elements(".AUCTION_STATS") %>% 
        html_element(".Astat_DATA") %>% 
        html_text()
      df_tbl <- bind_cols(tibble(auction_date), df_tbl)
      if (suppressWarnings(!is.null(df_tbl$x))) {
        df_tbl <- rename(df_tbl, city = x)
      } else {
        df_tbl <- mutate(df_tbl, city = NA_character_, 
                         property_address = NA_character_)
      }
      df_tbl <- df_tbl %>% 
        select(auction_date, final_judgment_amount, property_address, city) %>% 
        dplyr::filter(!is.na(city))
      # address checking
      if (is.null(suppressWarnings(df_tbl$property_address))) {
        auction_data <- NULL
      } else {
        auction_data <- df_tbl %>% 
          dplyr::filter(!is.na(property_address)) %>% 
          separate(city, into = c("city", "zip"), sep = ", ") %>% 
          mutate(auction_date = if_else(str_detect(auction_date, "^(\\d{2}/){2}\\d{4}"),
                                        str_extract(auction_date, "^(\\d{2}/){2}\\d{4}"),
                                        auction_date)) %>% 
          rename(judgment_amount = final_judgment_amount,
                 address = property_address)
      } # end of address checking
    } # end of auction waiting
    auction_data
  }) # end of map iteration
  auction_data <- do.call(bind_rows, auction_data)
  return(auction_data)
}
