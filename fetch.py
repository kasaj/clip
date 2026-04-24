import re
import requests
from bs4 import BeautifulSoup

_URL_RE = re.compile(r'^(https?://\S+|www\.\S+|[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(/\S*)?)$', re.IGNORECASE)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/120.0.0.0 Safari/537.36"
}


def is_url(text: str) -> bool:
    return bool(_URL_RE.match(text.strip()))


def _normalize_url(url: str) -> str:
    url = url.strip()
    if not url.startswith(("http://", "https://")):
        url = "https://" + url
    return url


def fetch_text(url: str, max_chars: int = 12000) -> str:
    resp = requests.get(_normalize_url(url), headers=HEADERS, timeout=15)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")

    # Remove scripts, styles, nav, footer
    for tag in soup(["script", "style", "nav", "footer", "header", "aside"]):
        tag.decompose()

    text = soup.get_text(separator="\n")
    # Collapse blank lines
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    result = "\n".join(lines)
    return result[:max_chars]
