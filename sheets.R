library(googlesheets4)

auction_data <- readRDS("auction.rds")
names(auction_data) <- c("Auction Date", "Judgment Amount", "Address", "City", "State", "Zip")

gs4_auth(path = Sys.getenv("CRED_PATH"))
sheet_write(auction_data, Sys.getenv("SHEETS_ID"), "Raw")
gs4_deauth()
