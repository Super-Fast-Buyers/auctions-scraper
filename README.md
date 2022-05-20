# Auction Scraping

[![scraper](https://github.com/akherlan/auctions-scraper/actions/workflows/scraper.yml/badge.svg)](https://github.com/akherlan/auctions-scraper/actions/workflows/scraper.yml)

**How is the script work?**

-   Scrape Auctions Waiting section from multiple subdomain of [\*.realforeclose.com](#)
-   Handle multiple pages of schedule ([sample](https://broward.realforeclose.com/index.cfm?zaction=USER&zmethod=CALENDAR))
-   Handle multiple slides with prev and next button in the preview item page ([sample](https://broward.realforeclose.com/index.cfm?zaction=AUCTION&Zmethod=PREVIEW&AUCTIONDATE=05/18/2022))
-   Filter data with only have following fields: property address, city, state, zip code
-   Filter only forclosure data available on website from given date until max 90 days run up
-   Scheduled running three times a week on Tuesday, Thursday, and Saturday at 12:01 AM UTC-4
-   Supply data to Google Sheets and save it historically
