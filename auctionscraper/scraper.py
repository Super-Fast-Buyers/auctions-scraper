from typing import Optional

from playwright.sync_api import sync_playwright
from playwright.sync_api import Page
from datetime import date, timedelta
import logging
import re

# Logger
logging.basicConfig(level=logging.DEBUG)

# <<<<<<< main
PAGE_DEFAULT_TIMEOUT = 90000
MAX_RETRY = 5



# def read_txt(txt: str):
# =======

def read_txt(txt:str):
# >>>>>>> main
    """ Read subdomain (county) from txt file """
    with open(txt, 'r') as f:
        return [line.strip() for line in f.readlines()]


def create_baseurl(subdomain: str, category: str) -> str:
    """ Create calendar URL """
    if category not in ['foreclose', 'taxdeed']:
        return ('Please define "foreclose" or "taxdeed" in category argument')
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

def page_request(page: Page, url: str, selector: str, timeout: int) \
        -> Optional[Page]:
    for retry_number in range(1, MAX_RETRY + 1):
        title_selector = "#Content_Title > h1"
        try:
            page.goto(url)
            title = page.wait_for_selector(title_selector,
                                           timeout=timeout)
            if title.text_content().upper() == 'OFFLINE':
                logging.info('Page response status OFFLINE')
                return None

            page.wait_for_selector(selector, timeout=timeout)
            return page
        except Exception as e:
            logging.info(f'RETRY: {retry_number} | error {e}')

def get_box_list(urls: list) -> list:
    """ Get box url from calendar page """
    data = []
    with sync_playwright() as p:
        # open browser
        browser = p.firefox.launch()
        page = browser.new_page()
        page.set_default_timeout(PAGE_DEFAULT_TIMEOUT)
        selector = '.CALDAYBOX'
        for url in urls:
            # access page
            logging.debug(f"GET {url} | LEVEL 1")
            response = page_request(page, url, selector, 5000)
            if response is None:
                logging.warning(f'Failed to GET {url}')
                continue

            data += parse_box(response)
        # close browser
        browser.close()
    return data

def get_data(urls: list):
    """ Get auction data """
    from playwright.sync_api import TimeoutError

    data = []
    with sync_playwright() as p:
        browser = p.firefox.launch()
        page = browser.new_page()
        page.set_default_timeout(PAGE_DEFAULT_TIMEOUT)
        selector = '#Area_W > .AUCTION_ITEM.PREVIEW'

        for url in urls:
            logging.debug(f"GET {url} | LEVEL 2")
            try:
                response_page = page_request(page, url, selector, 5000)
            except TimeoutError:
                logging.warning(f'Timeout on {url}')
                continue

            if response_page is None:
                logging.warning(f'Failed to GET {url}')
                continue

            cards = response_page.query_selector_all('#Area_W > .AUCTION_ITEM.PREVIEW')

            for card in cards:
                auction_date = re.sub(r'^.+AUCTIONDATE=(\d{2}/\d{2}/\d{4})$', '\\1', url)
                rows = card.query_selector_all('table.ad_tab tr')

                auction_info = {}
                pending_label = None

                for row in rows:
                    cells = row.query_selector_all('td')
                    if len(cells) != 2:
                        continue

                    label = cells[0].inner_text().strip().replace(":", "")
                    value = cells[1].inner_text().strip()

                    # Skip completely empty rows
                    if not label and not value:
                        continue

                    # Handle multi-line address continuation (label missing, value present)
                    if not label and pending_label == 'property_address':
                        auction_info['city'] = value
                        continue

                    key = label.lower().replace("#", "").replace(" ", "_") or "unknown_field"

                    # Store field
                    auction_info[key] = value
                    pending_label = key  # for next row context

                # Clean city, state, zip from combined field
                if 'city' in auction_info:
                    try:
                        city_part = auction_info['city'].split(',')
                        city = city_part[0].strip()
                        state_zip = city_part[1].strip()
                        state, zipcode = state_zip.split('-')
                    except Exception:
                        city, state, zipcode = auction_info['city'], 'FL', ''
                    auction_info.update({
                        'city': city,
                        'state': state.strip(),
                        'zipcode': zipcode.strip()
                    })

                auction_info['auction_date'] = auction_date
                data.append(auction_info)

        browser.close()
    return data


if __name__ == '__main__':
    pass
