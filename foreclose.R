# Activate selenium docker container
system("docker run -d -p 4445:4444 selenium/standalone-chrome:latest")

# Loading required settings
source("source.R") # generic functions
source("driver.R") # remote driver
source("auction.R") # main functions for pulling and pushing data

# Pulling data from website pages
pull_auction("foreclose")

# Pushing data to Google Sheets
push_auction("foreclose")
