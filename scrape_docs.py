import requests
from bs4 import BeautifulSoup
from markdownify import markdownify as md
from urllib.parse import urljoin, urlparse
import os

def scrape_and_convert(base_url, output_file):
    """
    Scrapes all linked documents from a base URL, converts them to Markdown,
    and saves them into a single file.
    """
    try:
        print(f"Fetching base URL: {base_url}")
        response = requests.get(base_url)
        response.raise_for_status()
        print("Successfully fetched base URL.")
    except requests.exceptions.RequestException as e:
        print(f"Error fetching base URL {base_url}: {e}")
        return

    soup = BeautifulSoup(response.content, 'html.parser')
    
    summary = soup.find('ul', class_='summary')
    if not summary:
        print("Could not find summary list (<ul class='summary'>). Falling back to find all links in the body.")
        summary = soup.find('body')
        if not summary:
            print("Could not find body. Aborting.")
            return

    links = []
    for a in summary.find_all('a', href=True):
        href = a['href']
        if '#' in href:
            href = href.split('#')[0]
        
        full_url = urljoin(base_url, href)
        if href and full_url not in links:
            links.append(full_url)

    print(f"Found {len(links)} unique links to scrape.")
    
    all_content_md = ""
    
    # Gitbook usually has an index.html, let's ensure it's first if not present
    index_url = urljoin(base_url, 'index.html')
    if index_url not in links:
        links.insert(0, index_url)

    for link in links:
        if not link.startswith(base_url):
             print(f"Skipping link that is not under the base URL: {link}")
             continue

        print(f"Scraping {link}...")
        
        try:
            page_response = requests.get(link)
            page_response.raise_for_status()
            
            page_soup = BeautifulSoup(page_response.content, 'html.parser')
            
            # Try to find the main content area of the page
            main_content = page_soup.find('main', role='main') or page_soup.find('section', class_='normal') or page_soup.find('body')
            
            if main_content:
                # Extract and remove the main h1 title to avoid duplication
                title_tag = main_content.find('h1')
                page_title = ""
                if title_tag:
                    page_title = title_tag.get_text().strip()
                    title_tag.decompose() # Remove the h1 tag from the content

                # Add the title back manually
                if page_title:
                    all_content_md += f"# {page_title}\n\n"

                markdown_content = md(str(main_content), heading_style="ATX")
                all_content_md += markdown_content + "\n\n---\n\n"
            else:
                print(f"Warning: Could not find main content for {link}")

        except requests.exceptions.RequestException as e:
            print(f"Error fetching {link}: {e}")
        except Exception as e:
            print(f"An error occurred while processing {link}: {e}")

    cleaned_md = clean_markdown(all_content_md)

    try:
        output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), output_file)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(cleaned_md)
        print(f"Successfully wrote all content to {output_path}")
    except IOError as e:
        print(f"Error writing to file {output_file}: {e}")


def clean_markdown(content):
    """
    Cleans the scraped markdown content.
    - Removes consecutive duplicate titles, even with blank lines in between.
    - Normalizes newlines and separators.
    """
    print("Cleaning markdown content...")
    lines = content.split('\n')
    cleaned_lines = []
    last_line = None
    for line in lines:
        current_line = line.strip()
        
        # Skip consecutive duplicate lines (especially for titles)
        if current_line and current_line == last_line and current_line.startswith('#'):
            continue
        
        # Avoid multiple consecutive blank lines
        if not current_line and (last_line is None or not last_line):
            continue

        cleaned_lines.append(line)
        if current_line: # Only update last_line if the line is not empty
            last_line = current_line
        else: # Allow one blank line
            last_line = ""

    # One more pass to handle titles separated by a blank line
    final_lines = []
    i = 0
    while i < len(cleaned_lines):
        final_lines.append(cleaned_lines[i])
        # Check if the next non-blank line is a duplicate title
        if cleaned_lines[i].strip().startswith('#'):
            j = i + 1
            while j < len(cleaned_lines) and not cleaned_lines[j].strip():
                j += 1 # Skip blank lines
            if j < len(cleaned_lines) and cleaned_lines[i].strip() == cleaned_lines[j].strip():
                i = j # Skip the duplicate title
            else:
                i += 1
        else:
            i += 1
    
    # Normalize separators
    content = "\n".join(final_lines)
    content = content.replace('\n\n\n---', '\n\n---\n')
    content = content.replace('---\n\n\n', '---\n\n')

    print("Cleaning complete.")
    return content


if __name__ == "__main__":
    BASE_URL = "http://oslab.mobisys.cc/lab2025/_book/"
    OUTPUT_FILE = "实验指导书.md"
    scrape_and_convert(BASE_URL, OUTPUT_FILE)
