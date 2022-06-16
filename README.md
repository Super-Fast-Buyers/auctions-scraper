# Auction Scraping

[![foreclose](https://github.com/Super-Fast-Buyers/auctions-scraper/actions/workflows/foreclose.yml/badge.svg)](https://github.com/Super-Fast-Buyers/auctions-scraper/actions/workflows/foreclose.yml)
[![taxdeed](https://github.com/Super-Fast-Buyers/auctions-scraper/actions/workflows/taxdeed.yml/badge.svg)](https://github.com/Super-Fast-Buyers/auctions-scraper/actions/workflows/taxdeed.yml)

**How is the script work?**

-   Scrape Forecloses and Taxdeeds (Auctions Waiting section) from multiple subdomain of [\*.realforeclose.com](#) and [\*.realtaxdeed.com](#)
-   Handle multiple pages of schedule ([sample](https://broward.realforeclose.com/index.cfm?zaction=USER&zmethod=CALENDAR))
-   Handle multiple slides with prev and next button in the preview item page ([sample](https://broward.realforeclose.com/index.cfm?zaction=AUCTION&Zmethod=PREVIEW&AUCTIONDATE=05/18/2022))
-   Filter data with only have following fields: property address, city, state, zip code
-   Filter Forclosures and Taxdeeds data available on websites from given date until max 90 days run up
-   Scheduled running three times a week on Tuesday, Thursday, and Saturday at 12:01 AM UTC-4
-   Supply data to Google Sheets and save it historically
