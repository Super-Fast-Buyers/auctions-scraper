from playwright.sync_api import sync_playwright, Page
from datetime import date, timedelta
import logging
import re

# Logger
logging.basicConfig(level=logging.DEBUG)


def read_txt(txt: str):
    """ Read subdomain (county) from txt file """
    with open(txt, 'r') as f:
        return [line.strip() for line in f.readlines()]


def create_baseurl(subdomain: str, category: str) -> str:
    """ Create calendar URL """
    if category not in ['foreclose', 'taxdeed']:
        return('Please define "foreclose" or "taxdeed" in category argument')
    else:
        return f"https://{subdomain}.real{category}.com/index.cfm?zaction=USER&zmethod=CALENDAR"


def create_calendar_url(baseurl:str, days=0) -> list:
    """ Get calendar pages to be scraped """
    tday = date.today() + timedelta(days=days)
    days_out = 90
    calendar = []
    month = []
    for day in range(0, days_out, 28):
        calendar_date = tday + timedelta(days=day)
        index = calendar_date.strftime('%m/%d/%Y').split('/')[0]
        if index not in month:
            month.append(index)
            date_url = calendar_date.strftime('%m/%d/%Y')
            calendar.append(baseurl + "&selCalDate=" + date_url)
    return calendar


def get_calendar_list(category: str, days: int) -> list:
    """ Get calendar url list to be scraped """
    calendar_url = []
    for subdomain in read_txt(f"{category}.txt"):
        baseurl = create_baseurl(subdomain, category)
        calendar_url += create_calendar_url(baseurl, days=days)
    return calendar_url


def parse_box(page: Page) -> list:
    """Parse URLs from the calendar page for auction schedules."""
    calendar_boxes = page.query_selector_all('div[class*=CALSEL], div[class*=CALSCH]')  # Include both CALSEL and CALSCH
    box_urls = []

    for box in calendar_boxes:
        try:
            day_id = box.get_attribute('dayid')
            category = 'Foreclosure' if 'foreclose' in page.url else 'Tax Deed'
            auction_info = box.query_selector('.CALTEXT').inner_text()
            scheduled_auctions = box.query_selector('.CALSCH').inner_text().strip()

            if category in auction_info and int(scheduled_auctions) > 0:
                url = page.url.split('?')[0] + f"?zaction=AUCTION&Zmethod=PREVIEW&AUCTIONDATE={day_id}"
                box_urls.append(url)
                logging.debug(f"Auction schedule found, URL added: {url}")
        except Exception as e:
            logging.warning(f"Error parsing box for day ID {day_id}: {e}")

    return box_urls



def get_box_list(urls: list) -> list:
    """Get box URLs from calendar pages and check for active auctions."""
    data = []
    
    with sync_playwright() as p:
        browser = p.firefox.launch()
        page = browser.new_page()
        page.set_default_timeout(90000)
        
        for url in urls:
            logging.debug(f"GET {url} | LEVEL 1")
            try:
                page.goto(url)
                page.wait_for_selector('.CALDAYBOX')
                data += parse_box(page)
            except Exception as e:
                logging.warning(f"Failed to GET {url}: {e}")
                continue
        
        browser.close()
        
    return data


def scrape_auction_items(page: Page):
    """Scrape auction items from the current page, focusing only on '3rd Party Bidder' data."""
    auction_items = page.query_selector_all('#Area_C .AUCTION_ITEM.PREVIEW')
    auction_data = []

    for auction_item in auction_items:
        # Extract the Sold To field
        sold_to_element = auction_item.query_selector('.ASTAT_MSG_SOLDTO_MSG')
        sold_to = sold_to_element.inner_text().strip() if sold_to_element else None

        # Check if the auction was sold to a "3rd Party Bidder"
        if sold_to and "3rd Party Bidder" in sold_to:
            # Extract auction date and time
            auction_date_time_element = auction_item.query_selector('.ASTAT_MSGB')
            auction_date_time = auction_date_time_element.inner_text().strip() if auction_date_time_element else 'Unknown'
            auction_date, auction_time = auction_date_time.split(' ', 1) if ' ' in auction_date_time else (auction_date_time, 'Unknown')

            # Initialize auction info
            auction_info = {
                'auction_date': auction_date,
                'auction_time': auction_time,
                'sold_to': sold_to
            }

            # Extract auction details from the table
            auction_details = {}
            auction_fields = auction_item.query_selector_all('tr > th')
            auction_values = auction_item.query_selector_all('tr > td')

            for i in range(len(auction_fields)):
                field = auction_fields[i].inner_text().strip().lower().replace(':', '').replace(' ', '_')
                value = auction_values[i].inner_text().strip()

                # Map specific fields to desired format
                if field == "auction_type":
                    auction_details["auction_type"] = value
                elif field == "case_#":
                    auction_details["case_number"] = value
                elif field == "final_judgment_amount":
                    auction_details["final_judgment_amount"] = value
                elif field == "parcel_id":
                    auction_details["parcel_id"] = value
                elif field == "property_address":
                    auction_details["property_address"] = value
                elif field == "assessed_value":
                    auction_details["assessed_value"] = value
                elif field == "plaintiff_max_bid":
                    auction_details["plaintiff_max_bid"] = value

            # Extract sold amount from auction stats
            sold_amount_element = auction_item.query_selector('.ASTAT_MSGD')
            auction_info['sold_amount'] = sold_amount_element.inner_text().strip() if sold_amount_element else 'Unknown'

            # Update auction_info with details
            auction_info.update(auction_details)

            auction_data.append(auction_info)

            # Log the extracted auction information
            logging.info(f"Extracted auction info: {auction_info}")

    # Log if no '3rd Party Bidder' auctions were found
    if not auction_data:
        logging.info("No 3rd Party Bidder found")
    
    return auction_data


def get_data(urls: list):
    """ Get auction data only for 3rd Party Bidders. """
    data = []
    # open browser
    with sync_playwright() as p:
        browser = p.firefox.launch()
        page = browser.new_page()
        page.set_default_timeout(90000)
        
        for url in urls:
            # access page
            logging.debug(f"GET {url} | LEVEL 2")
            try:
                page.goto(url)
                page.wait_for_selector('#Area_C > .AUCTION_ITEM.PREVIEW')
                auction_data = scrape_auction_items(page)
                data.extend(auction_data)  # Only add 3rd Party Bidder data
            except Exception as e:
                logging.warning(f"Failed to GET {url}: {e}")
                continue
        
        # close browser
        browser.close()
        
    return data


if __name__ == '__main__':
    pass
