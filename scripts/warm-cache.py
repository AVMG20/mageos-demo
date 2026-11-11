#!/usr/bin/env python3
"""Warm Magento's full page cache by crawling every storefront page.

Starts at the homepage, follows same-host links breadth-first and requests each
cacheable page once, so the next visitor gets it from the full page cache (Valkey).
Pages that Magento never caches (cart, checkout, account, search, ...) are skipped.

Only uses the Python standard library:

    python3 scripts/warm-cache.py                       # https://mageos.bitploy.nl/
    python3 scripts/warm-cache.py --concurrency 8 --max-pages 200
    python3 scripts/warm-cache.py https://other-shop.example/ --with-query
"""

import argparse
import gzip
import sys
import threading
import time
import zlib
from collections import deque
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import urldefrag, urljoin, urlsplit, urlunsplit
from urllib.request import Request, urlopen

DEFAULT_URL = "https://mageos.bitploy.nl/"
USER_AGENT = "mageos-cache-warmer/1.0"

# Path prefixes that are never served from the full page cache (or are not pages at all).
SKIP_PREFIXES = (
    "/admin", "/checkout", "/customer", "/wishlist", "/sales", "/catalogsearch",
    "/review/customer", "/newsletter/manage", "/sendfriend", "/productalert",
    "/multishipping", "/vault", "/downloadable/customer", "/paypal", "/persistent",
    "/rest", "/graphql", "/soap", "/static", "/media", "/errors", "/rma",
    "/catalog/product_compare", "/oauth", "/stores/store/redirect", "/directory/currency",
)
SKIP_EXTENSIONS = (
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif", ".svg", ".ico", ".css", ".js",
    ".json", ".xml", ".pdf", ".zip", ".woff", ".woff2", ".ttf", ".mp4", ".txt",
)


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.links.append(href)


def normalize(url, base_host, with_query):
    """Absolute, fragment-free URL on the shop's host, or None when it should not be warmed."""
    url, _ = urldefrag(url.strip())
    parts = urlsplit(url)
    if parts.scheme not in ("http", "https") or parts.netloc != base_host:
        return None
    path = parts.path or "/"
    lower = path.lower()
    if lower.startswith(SKIP_PREFIXES) or lower.endswith(SKIP_EXTENSIONS):
        return None
    if parts.query and not with_query:
        return None
    return urlunsplit((parts.scheme, parts.netloc, path, parts.query if with_query else "", ""))


def fetch(url, timeout):
    """Request one page; returns (status, seconds, html or '')."""
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html",
                                    "Accept-Encoding": "gzip, deflate"})
    start = time.monotonic()
    try:
        with urlopen(request, timeout=timeout) as response:
            body = response.read()
            status = response.status
            encoding = response.headers.get("Content-Encoding", "")
            content_type = response.headers.get("Content-Type", "")
    except HTTPError as error:
        return error.code, time.monotonic() - start, ""
    except (URLError, TimeoutError, OSError) as error:
        return f"ERR {getattr(error, 'reason', error)}", time.monotonic() - start, ""
    elapsed = time.monotonic() - start
    if encoding == "gzip":
        body = gzip.decompress(body)
    elif encoding == "deflate":
        body = zlib.decompress(body)
    html = body.decode("utf-8", "replace") if "html" in content_type else ""
    return status, elapsed, html


def main():
    parser = argparse.ArgumentParser(description="Warm the Magento full page cache by crawling the storefront.")
    parser.add_argument("url", nargs="?", default=DEFAULT_URL, help=f"start URL (default {DEFAULT_URL})")
    parser.add_argument("-c", "--concurrency", type=int, default=4, help="parallel requests (default 4)")
    parser.add_argument("-n", "--max-pages", type=int, default=5000, help="stop after this many pages (default 5000)")
    parser.add_argument("-t", "--timeout", type=float, default=60, help="seconds per request (default 60)")
    parser.add_argument("--with-query", action="store_true",
                        help="also warm URLs with a query string (layered navigation filters, sorting); can be many")
    parser.add_argument("-q", "--quiet", action="store_true", help="only print failures and the summary")
    args = parser.parse_args()

    base_host = urlsplit(args.url).netloc
    start_url = normalize(args.url, base_host, args.with_query) or args.url
    seen = {start_url}
    queue = deque([start_url])
    lock = threading.Lock()
    results = []  # (url, status, seconds)
    started = time.monotonic()

    def work(url):
        status, seconds, html = fetch(url, args.timeout)
        found = []
        if html:
            link_parser = LinkParser()
            link_parser.feed(html)
            for href in link_parser.links:
                link = normalize(urljoin(url, href), base_host, args.with_query)
                if link:
                    found.append(link)
        return url, status, seconds, found

    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        running = set()
        while queue or running:
            while queue and len(running) < args.concurrency and len(results) + len(running) < args.max_pages:
                running.add(pool.submit(work, queue.popleft()))
            if not running:
                break
            done, running = wait(running, return_when=FIRST_COMPLETED)
            for future in done:
                url, status, seconds, found = future.result()
                with lock:
                    results.append((url, status, seconds))
                    for link in found:
                        if link not in seen:
                            seen.add(link)
                            queue.append(link)
                ok = status == 200
                if not args.quiet or not ok:
                    print(f"[{len(results):>5}] {status} {seconds:6.2f}s  {url}", flush=True)

    total = time.monotonic() - started
    ok = [r for r in results if r[1] == 200]
    failed = [r for r in results if r[1] != 200]
    times = sorted(r[2] for r in ok)
    print()
    print(f"Warmed {len(ok)} pages in {total:.0f}s ({len(failed)} not 200, {len(queue)} left unvisited)")
    if times:
        print(f"  median {times[len(times) // 2]:.2f}s, slowest {times[-1]:.2f}s")
    for url, status, _ in failed[:20]:
        print(f"  {status}  {url}")
    if len(results) >= args.max_pages and queue:
        print(f"  hit --max-pages {args.max_pages}; raise it to warm the rest")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
