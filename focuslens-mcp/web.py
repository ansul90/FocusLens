"""DuckDuckGo HTML search + page-summary fetch. No API key."""
from __future__ import annotations

import re
from typing import TypedDict
from urllib.parse import parse_qs, urlparse

import httpx
from bs4 import BeautifulSoup

DDG_URL = "https://html.duckduckgo.com/html/"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)
TIMEOUT = httpx.Timeout(10.0, connect=5.0)
MAX_RESULTS = 5
MAX_PAGE_BYTES = 200_000


class SearchResult(TypedDict):
    title: str
    url: str
    snippet: str


class PageSummary(TypedDict):
    url: str
    title: str
    description: str


def _clean_redirect(href: str) -> str:
    """DDG wraps result URLs in /l/?uddg=<encoded>. Unwrap them."""
    if href.startswith("//"):
        href = "https:" + href
    parsed = urlparse(href)
    if parsed.path.startswith("/l/") and parsed.query:
        qs = parse_qs(parsed.query)
        if "uddg" in qs:
            return qs["uddg"][0]
    return href


def search(query: str, limit: int = 3) -> list[SearchResult]:
    limit = max(1, min(limit, MAX_RESULTS))
    with httpx.Client(timeout=TIMEOUT, headers={"User-Agent": USER_AGENT}) as client:
        resp = client.post(DDG_URL, data={"q": query})
        resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    results: list[SearchResult] = []
    for node in soup.select("div.result")[: limit * 2]:
        a = node.select_one("a.result__a")
        snippet_node = node.select_one("a.result__snippet, div.result__snippet")
        if not a or not a.get("href"):
            continue
        url = _clean_redirect(a["href"])
        results.append(
            SearchResult(
                title=a.get_text(strip=True),
                url=url,
                snippet=snippet_node.get_text(" ", strip=True) if snippet_node else "",
            )
        )
        if len(results) >= limit:
            break
    return results


def fetch_summary(url: str) -> PageSummary:
    """Fetch a page and return its <title> + meta description."""
    with httpx.Client(
        timeout=TIMEOUT, headers={"User-Agent": USER_AGENT}, follow_redirects=True
    ) as client:
        resp = client.get(url)
        resp.raise_for_status()
        body = resp.content[:MAX_PAGE_BYTES]
    soup = BeautifulSoup(body, "html.parser")
    title_el = soup.find("title")
    title = title_el.get_text(strip=True) if title_el else ""
    description = ""
    for selector in [
        ('meta[name="description"]', "content"),
        ('meta[property="og:description"]', "content"),
    ]:
        node = soup.select_one(selector[0])
        if node and node.get(selector[1]):
            description = re.sub(r"\s+", " ", node[selector[1]]).strip()
            break
    return PageSummary(url=url, title=title, description=description)
