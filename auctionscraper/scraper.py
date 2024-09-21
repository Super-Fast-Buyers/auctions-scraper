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
        return 'Please define "foreclose" or "taxdeed" in category argument'
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
    """ Get box URLs from calendar pages and check for active auctions. """
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


    """ Get auction data only for 3rd Party Bidders. """
    data = []
    with sync_playwright() as p:
        browser = p.firefox.launch()
        page = browser.new_page()
        page.set_default_timeout(60000)

        for url in urls:
            logging.debug(f"GET {url} | LEVEL 2")
            try:
                page.goto(url)
                page.wait_for_selector('#Area_C > .AUCTION_ITEM.PREVIEW')
                auction_data = scrape_auction_items(page)
                data.extend(auction_data)
            except Exception as e:
                logging.warning(f"Failed to GET {url}: {e}")

        browser.close()
    
    return data



def scrape_auction_items(page):
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
    'sold_to': sold_to,
    'sold_amount': "Not Found",
    'auction_type': "Not Found",
    'case_number': "Not Found",
    'final_judgment_amount': "Not Found",
    'parcel_id': "Not Found",
    'property_address': "Not Found", 
    'city': "Not Found",
    'state': "Not Found",
    'zip_code': "Not Found",
    'assessed_value': "Not Found",
    'plaintiff_max_bid': "Not Found",
    'opening_bid': "Not Found",  # Add a comma here
    'surplus_amount': "Not Found",  # Add a colon here
    'certificate_number': "Not Found",
}


            # Extract auction details from the table
            auction_details = {}
            auction_rows = auction_item.query_selector_all('tr')

            for row in auction_rows:
                field_element = row.query_selector('th')
                value_element = row.query_selector('td')
                
                if field_element and value_element:
                    field = field_element.inner_text().strip().lower().replace(':', '').replace(' ', '_')
                    value = value_element.inner_text().strip()

                    # Map specific fields to desired format
                    if field == "auction_type":
                        auction_details["auction_type"] = value
                    elif field == "case_#":
                        auction_details["case_number"] = value
                    elif field == "final_judgment_amount":
                        auction_details["final_judgment_amount"] = value
                    elif field == "certificate_#":
                        auction_info["certificate_number"] = value
                    elif field == "opening_bid":
                        auction_details["opening_bid"] = value
                    elif field == "parcel_id":
                        auction_details["parcel_id"] = value
                    elif field == "property_address":
                        auction_details["property_address"] = value
                    elif field == "assessed_value":
                        auction_details["assessed_value"] = value
                    elif field == "plaintiff_max_bid":
                        auction_details["plaintiff_max_bid"] = value
                    
                    # Handle missing field labels (e.g., city/state/zip row)
                    elif field == "":
                        try:
                            # Assuming it's the city/state/zip row when the label is missing
                            city_state_zip = value
                            # Split city, state, and zip
                            city, state_zip = city_state_zip.split(',', 1)
                            state, zip_code = state_zip.strip().split('-')
                            auction_details["city"] = city.strip()
                            auction_details["state"] = state.strip()
                            auction_details["zip_code"] = zip_code.strip()
                        except ValueError:
                            logging.warning(f"Could not parse city, state, and zip from: {value}")
                            auction_details["city_state_zip"] = value

            # Extract sold amount from auction stats
            sold_amount_element = auction_item.query_selector('.ASTAT_MSGD')
            auction_info['sold_amount'] = sold_amount_element.inner_text().strip() if sold_amount_element else 'Unknown'
            

            # Update auction_info with details
            auction_info.update(auction_details)

              # Extract and calculate the difference between final_judgment_amount and plaintiff_max_bid
            try:
                # Convert amounts to float if available
                sold_amount = float(auction_info['sold_amount'].replace("$", "").replace(",", "")) if auction_info['sold_amount'] != "Unknown" else None
                opening_bid = float(auction_info['opening_bid'].replace("$", "").replace(",", "")) if auction_info['opening_bid'] != "Not Found" else None
                final_judgment_amount = float(auction_info['final_judgment_amount'].replace("$", "").replace(",", "")) if auction_info['final_judgment_amount'] != "Not Found" else None
               
                # Calculate surplus_amount
                if sold_amount is not None and final_judgment_amount is not None:
                    auction_info['surplus_amount'] = sold_amount - final_judgment_amount
                elif opening_bid is not None and sold_amount is not None:
                    auction_info['surplus_amount'] = sold_amount - opening_bid
                else:
                    auction_info['surplus_amount'] = "Not Calculable"
              
            except ValueError as e:
                auction_info['surplus_amount'] = "Not Calculable"
                logging.warning(f"Could not calculate surplus_amount for auction: {auction_info['case_number']}, Error: {e}")

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
        browser = p.firefox.launch(headless=True)  # Use headless mode for performance
        page = browser.new_page()
        page.set_default_timeout(60000)  # Default timeout

        for url in urls:
            # access page
            logging.debug(f"GET {url} | LEVEL 2")
            try:
                page.goto(url)
                page.wait_for_load_state('networkidle')  # Wait for page to fully load

                # Check if the auction items selector is present
                if page.query_selector('#Area_C > .AUCTION_ITEM.PREVIEW'):
                    auction_data = scrape_auction_items(page)
                    data.extend(auction_data)  # Only add 3rd Party Bidder data
                else:
                    logging.info(f"No auction items found on page: {url}")

            except Exception as e:
                logging.warning(f"Failed to GET {url}: {e}")
                continue
        
        # close browser
        browser.close()
        
    return data
if __name__ == '__main__':
    pass
