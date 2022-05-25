library(googlesheets4)

auction_data <- readRDS("auction.rds")
names(auction_data) <- c(
  "Auction Date", 
  "Judgment Amount", 
  "Address", "City", 
  "State", 
  "Zip",
  "Date Added"
)

gs4_auth(path = Sys.getenv("CRED_PATH"))
tryCatch({
  sheet_write(auction_data, Sys.getenv("SHEETS_ID"), "Raw")
  message("Data is available on Google Sheets!")
}, error = function(e) message("Cannot send data to Google Sheets!"))
gs4_deauth()
