from auctionscraper import scraper
import logging
import json

logging.basicConfig(level=logging.DEBUG)

def scrape(category:str, output:str):
    # LEVEL 1 - scrape schedules from calendars
    # argument days is the number of day start from today
    calendar_url_list = scraper.get_calendar_list(category, days=0)
    box_url_list = scraper.get_box_list(calendar_url_list)
    # LEVEL 2 - scrape the real data
    data = scraper.get_data(box_url_list)
    # save data
    with open(output, 'w') as fout:
         json.dump(data, fout)
         logging.info(f"Data saved to {output}")

if __name__ == '__main__':
    scrape('foreclose', 'history/foreclose.json')
    scrape('taxdeed', 'history/taxdeed.json')