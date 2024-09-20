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


def create_calendar_url(baseurl: str, days=0) -> list:
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
    """ Parse url from box calendar """
    calendar_box = page.query_selector_all('div[class*=CALSEL]')  # could be CALSEF, CALSET, CALSELB
    box_url = []
    for box in calendar_box:
        day_id = box.get_attribute('dayid')
        if 'foreclose' in re.findall(r'(?<=real)\w+(?=\.com)', page.url):
            category = r'Foreclosure'
        elif 'taxdeed' in re.findall(r'(?<=real)\w+(?=\.com)', page.url):
            category = r'Tax Deed'
        else:
            logging.warning(f"Something wrong when parsing category at ({day_id}): {page.url}")
            continue
        if re.findall(category, box.query_selector('.CALTEXT').inner_text()):
            if int(box.query_selector('.CALACT').inner_text()) > 0:
                url = page.url.split('?')[0] + f"?zaction=AUCTION&Zmethod=PREVIEW&AUCTIONDATE={day_id}"
                box_url.append(url)
    return box_url


def get_box_list(urls: list) -> list:
    """ Get box url from calendar page """
    data = []
    with sync_playwright() as p:
        # open browser
        browser = p.firefox.launch()
        page = browser.new_page()
        page.set_default_timeout(90000)
        for url in urls:
            # access page
            logging.debug(f"GET {url} | LEVEL 1")
            try:
                page.goto(url)
                page.wait_for_selector('.CALDAYBOX')
                # parse content
                data += parse_box(page)
            except Exception as e:
                logging.warning(f"Failed to GET {url}: {e}")
                continue
        # close browser
        browser.close()
    return data


def scrape_auction_items(page: Page):
    """ Scrape auction items from the current page, only storing '3rd Party Bidder' data and printing to console """
    auction_items = page.query_selector_all('#Area_C > .AUCTION_ITEM.PREVIEW')
    auction_data = []

    for auction_item in auction_items:
        # Extract auction date and time
        auction_date_time_element = auction_item.query_selector('.ASTAT_MSGB')
        auction_date_time = auction_date_time_element.inner_text().strip() if auction_date_time_element else 'Unknown'
        auction_date, auction_time = auction_date_time.split(' ', 1) if ' ' in auction_date_time else (auction_date_time, 'Unknown')

        # Extract the "Sold To" field
        sold_to_element = auction_item.query_selector('.ASTAT_MSG_SOLDTO_MSG')
        sold_to = sold_to_element.inner_text().strip() if sold_to_element else None

        # Only store if sold to "3rd Party Bidder"
        if sold_to == "3rd Party Bidder":
            auction_info = {
                'auction_date': auction_date,
                'auction_time': auction_time,
                'sold_to': sold_to
            }

            # Extract auction details from the table
            auction_details = {}
            auction_fields = auction_item.query_selector_all('tr > th')
            auction_values = auction_item.query_selector_all('tr > td')

            if len(auction_fields) == len(auction_values):
                for i in range(len(auction_fields)):
                    field = auction_fields[i].inner_text().strip().lower().replace(':', '').replace(' ', '_')
                    value = auction_values[i].inner_text().strip()

                    # Map specific fields to desired format
                    if field == "case_#":
                        auction_details["case_number"] = value
                    elif field == "certificate_#":
                        auction_details["certificate_number"] = value
                    elif field == "opening_bid":
                        auction_details["opening_bid"] = value
                    elif field == "parcel_id":
                        auction_details["parcel_id"] = value
                    elif field == "property_address":
                        auction_details["property_address"] = value
                    elif field == "assessed_value":
                        auction_details["assessed_value"] = value
                    elif field == "":
                        auction_details["city_state_zip"] = value
                    elif field == "auction_type":
                        auction_details["auction_type"] = value

            auction_info.update(auction_details)

            # Print found auction details to the console
            print(f"Found auction data for 3rd Party Bidder:\n{auction_info}\n")
            auction_data.append(auction_info)

    # Log if no '3rd Party Bidder' auctions were found
    if not auction_data:
        logging.info("No 3rd Party Bidder found")
        print("No 3rd Party Bidder found")
        
    return auction_data

def get_data(urls: list):
    """ Get auction data, only storing '3rd Party Bidder' auctions and printing results """
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
                page.wait_for_selector('#Area_W > .AUCTION_ITEM.PREVIEW')
                auction_data = scrape_auction_items(page)  # Get only '3rd Party Bidder' data
                if auction_data:
                    data += auction_data  # Store data only if there are valid auctions
                else:
                    logging.info(f"No 3rd Party Bidder found on page: {url}")
                    print(f"No 3rd Party Bidder found on page: {url}")
            except Exception as e:
                logging.warning(f"Failed to GET {url}: {e}")
                print(f"Failed to GET {url}: {e}")
                continue
        # close browser
        browser.close()
    return data

if __name__ == '__main__':
    pass