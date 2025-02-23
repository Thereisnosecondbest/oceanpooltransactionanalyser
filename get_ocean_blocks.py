# Updated get_ocean_blocks.py with English comments

import requests
from bs4 import BeautifulSoup
import csv
import re
import time

BASE_URL = "https://www.ocean.xyz/template/blocks/rows"
TARGET_HEIGHT = 819242  # Stop scraping once this block height is found

def scrape_ocean_until_block(target_block=TARGET_HEIGHT, output_csv='ocean_blocks.csv'):
    """
    Starts from bpage=0, page=1 and increments both parameters sequentially.
    Parses the block table on each page and collects data until the target block height is found.
    Stores all the block data into a CSV file.
    """
    bpage = 0
    page = 1
    all_rows = []  # Accumulate all block data rows

    while True:
        url = f"{BASE_URL}?bpage={bpage}&page={page}"
        print(f"Requesting: {url}")

        # Parse block data from the current page
        data_list = fetch_ocean_block_table(url)

        # If no blocks are found on the current page, terminate scraping
        if not data_list:
            print("No blocks found on this page. Stopping.")
            break

        # Check if the target block height is found
        found_target = False
        for row in data_list:
            all_rows.append(row)
            if str(row["Height"]) == str(target_block):
                print(f"Found target block {target_block}, stopping.")
                found_target = True
                break

        if found_target:
            break

        # Move to the next page
        bpage += 1
        page += 1
        time.sleep(1)  # Delay to avoid sending requests too quickly

    # Save all block data to CSV
    _save_to_csv(all_rows, output_csv)
    print(f"Scraping finished. {len(all_rows)} rows saved to '{output_csv}'.")

def fetch_ocean_block_table(url):
    """
    Fetches block data from the given URL and parses relevant block information.
    Extracts [DateTime, Shares, Difficulty, Address, Worker, Height, BlockHash].
    Returns an empty list if no data is found.
    """
    try:
        resp = requests.get(url, timeout=10)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"Error fetching {url}: {e}")
        return []

    soup = BeautifulSoup(resp.text, 'html.parser')
    rows = soup.find_all('tr', class_='table-row')
    if not rows:
        return []

    data_list = []
    for row in rows:
        cols = row.find_all('td', class_='table-cell')
        if len(cols) < 6:
            continue

        date_time = cols[0].get_text(strip=True)
        shares = cols[1].get_text(strip=True)
        difficulty = cols[2].get_text(strip=True)
        address, worker = parse_address_worker(cols[3])
        height = cols[4].get_text(strip=True)
        block_hash = cols[5].find('a').get_text(strip=True) if cols[5].find('a') else ""

        row_data = {
            "DateTime": date_time,
            "Shares": shares,
            "Difficulty": difficulty,
            "Address": address,
            "Worker": worker,
            "Height": height,
            "BlockHash": block_hash
        }
        data_list.append(row_data)

    return data_list

def parse_address_worker(td_tag):
    """
    Extracts Address and Worker information from the 4th table cell.
    Parses the tooltip or extracts from the hyperlink if necessary.
    """
    address = ""
    worker = ""
    span_tooltip = td_tag.find('span', class_='tooltiptext-worker')
    if span_tooltip:
        tooltip_text = span_tooltip.get_text(strip=True)
        match = re.search(r'User:\s*([^\s]+).*?Worker:\s*([^\s]+)', tooltip_text)
        if match:
            address = match.group(1)
            worker = match.group(2)
    else:
        a_tag = td_tag.find('a', href=re.compile(r'/stats/'))
        if a_tag:
            href = a_tag.get('href', '')
            m = re.search(r'/stats/(.+)', href)
            if m:
                address = m.group(1).strip()

    return address, worker

def _save_to_csv(data_rows, filename):
    """
    Saves the block data into a CSV file.
    """
    fieldnames = ["DateTime", "Shares", "Difficulty", "Address", "Worker", "Height", "BlockHash"]
    with open(filename, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in data_rows:
            writer.writerow(row)

if __name__ == "__main__":
    scrape_ocean_until_block()
