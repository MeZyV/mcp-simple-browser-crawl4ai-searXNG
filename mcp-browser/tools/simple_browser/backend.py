"""
Simple backend for the simple browser tool.
"""

import functools
import asyncio
import logging
import os
from abc import abstractmethod
from importlib.metadata import version
from typing import Callable, ParamSpec, TypeVar
from urllib.parse import quote

import chz
from aiohttp import ClientSession, ClientTimeout
from tenacity import (
    after_log,
    before_sleep_log,
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from .page_contents import (
    Extract,
    FetchResult,
    PageContents,
    get_domain,
    process_html,
    process_markdown,
    process_search_results
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)



VIEW_SOURCE_PREFIX = "view-source:"

try:
    _GPT_OSS_VERSION = version("gpt-oss")
except Exception:
    _GPT_OSS_VERSION = "0.0.8"  # fallback version


class BackendError(Exception):
    pass


P = ParamSpec("P")
R = TypeVar("R")


def with_retries(
    func: Callable[P, R],
    num_retries: int,
    max_wait_time: float,
) -> Callable[P, R]:
    if num_retries > 0:
        retry_decorator = retry(
            stop=stop_after_attempt(num_retries),
            wait=wait_exponential(
                multiplier=1,
                min=2,
                max=max_wait_time,
            ),
            before_sleep=before_sleep_log(logger, logging.INFO),
            after=after_log(logger, logging.INFO),
            retry=retry_if_exception_type(Exception),
        )
        return retry_decorator(func)
    else:
        return func


def maybe_truncate(text: str, num_chars: int = 1024) -> str:
    if len(text) > num_chars:
        text = text[: (num_chars - 3)] + "..."
    return text


@chz.chz(typecheck=True)
class Backend:
    source: str = chz.field(doc="Description of the backend source")

    @abstractmethod
    async def search(
        self,
        query: str,
        topn: int,
        session: ClientSession,
    ) -> PageContents:
        pass

    @abstractmethod
    async def fetch(self, url: str, session: ClientSession) -> PageContents:
        pass

    async def _post(self, session: ClientSession, endpoint: str, payload: dict) -> dict:
        headers = {
            "x-api-key": self._get_api_key(),
            "user-agent": f"gpt-oss/{_GPT_OSS_VERSION}",
        }
        async with session.post(f"{self.BASE_URL}{endpoint}", json=payload, headers=headers) as resp:
            if resp.status != 200:
                raise BackendError(
                    f"{self.__class__.__name__} error {resp.status}: {await resp.text()}"
                )
            return await resp.json()

    async def _get(self, session: ClientSession, endpoint: str, params: dict) -> dict:
        headers = {
            "x-api-key": self._get_api_key(),
            "user-agent": f"gpt-oss/{_GPT_OSS_VERSION}",
        }
        async with session.get(f"{self.BASE_URL}{endpoint}", params=params, headers=headers) as resp:
            if resp.status != 200:
                raise BackendError(
                    f"{self.__class__.__name__} error {resp.status}: {await resp.text()}"
                )
            return await resp.json()


@chz.chz(typecheck=True)
class ExaBackend(Backend):
    """Backend that uses the Exa Search API."""

    source: str = chz.field(doc="Description of the backend source")
    api_key: str | None = chz.field(
        doc="Exa API key. Uses EXA_API_KEY environment variable if not provided.",
        default=None,
    )

    BASE_URL: str = "https://api.exa.ai"

    def _get_api_key(self) -> str:
        key = self.api_key or os.environ.get("EXA_API_KEY")
        if not key:
            raise BackendError("Exa API key not provided")
        return key


    async def search(
        self, query: str, topn: int, session: ClientSession
    ) -> PageContents:
        data = await self._post(
            session,
            "/search",
            {"query": query, "numResults": topn, "contents": {"text": True, "summary": True}},
        )
        # make a simple HTML page to work with browser format
        titles_and_urls = [
            (result["title"], result["url"], result["summary"])
            for result in data["results"]
        ]
        html_page = f"""
<html><body>
<h1>Search Results</h1>
<ul>
{"".join([f"<li><a href='{url}'>{title}</a> {summary}</li>" for title, url, summary in titles_and_urls])}
</ul>
</body></html>
"""

        return process_html(
            html=html_page,
            url="",
            title=query,
            display_urls=True,
            session=session,
        )

    async def fetch(self, url: str, session: ClientSession) -> PageContents:
        is_view_source = url.startswith(VIEW_SOURCE_PREFIX)
        if is_view_source:
            url = url[len(VIEW_SOURCE_PREFIX) :]
        data = await self._post(
            session,
            "/contents",
            {"urls": [url], "text": { "includeHtmlTags": True }},
        )
        results = data.get("results", [])
        if not results:
            raise BackendError(f"No contents returned for {url}")
        return process_html(
            html=results[0].get("text", ""),
            url=url,
            title=results[0].get("title", ""),
            display_urls=True,
            session=session,
        )

@chz.chz(typecheck=True)
class YouComBackend(Backend):
    """Backend that uses the You.com Search API."""

    source: str = chz.field(doc="Description of the backend source")

    BASE_URL: str = "https://api.ydc-index.io"

    def _get_api_key(self) -> str:
        key = os.environ.get("YDC_API_KEY")
        if not key:
            raise BackendError("You.com API key not provided")
        return key

    
    async def search(
        self, query: str, topn: int, session: ClientSession
    ) -> PageContents:
        data = await self._get(
            session,
            "/v1/search",
            {"query": query, "count": topn},
        )
        # make a simple HTML page to work with browser format
        web_titles_and_urls, news_titles_and_urls = [], []
        if "web" in data["results"]:
            web_titles_and_urls = [
                (result["title"], result["url"], result["snippets"])
                for result in data["results"]["web"]
            ]
        if "news" in data["results"]:
            news_titles_and_urls = [
                (result["title"], result["url"], result["description"])
                for result in data["results"]["news"]
            ]
        titles_and_urls = web_titles_and_urls + news_titles_and_urls
        html_page = f"""
<html><body>
<h1>Search Results</h1>
<ul>
{"".join([f"<li><a href='{url}'>{title}</a> {summary}</li>" for title, url, summary in titles_and_urls])}
</ul>
</body></html>
"""

        return process_html(
            html=html_page,
            url="",
            title=query,
            display_urls=True,
            session=session,
        )

    async def fetch(self, url: str, session: ClientSession) -> PageContents:
        is_view_source = url.startswith(VIEW_SOURCE_PREFIX)
        if is_view_source:
            url = url[len(VIEW_SOURCE_PREFIX) :]
        data = await self._post(
            session,
            "/v1/contents",
            {"urls": [url], "livecrawl_formats": "html"},
        )
        if not data:
            raise BackendError(f"No contents returned for {url}")
        if "html" not in data[0]:
            raise BackendError(f"No HTML returned for {url}")
        return process_html(
            html=data[0].get("html", ""),
            url=url,
            title=data[0].get("title", ""),
            display_urls=True,
            session=session,
        )
    
@chz.chz(typecheck=True)
class SearxngCrawlBackend(Backend):
    """
    Backend using local SearXNG for search and Crawl4AI for page fetching.

    search() -> SearXNG JSON API
    fetch()  -> Crawl4AI /scrape (markdown-first)
    """
    source: str = chz.field(default="web")
    searxng_url: str = chz.field(default="")
    crawl4ai_url: str = chz.field(default="")
    crawl4ai_api_token: str | None = chz.field(default=None)
    num_retries: int = chz.field(default=3)
    max_wait_time: float = chz.field(default=10.0)
    fetch_timeout: int = chz.field(default=30000)

    def _get_searxng_url(self) -> str:
        return (self.searxng_url or os.environ.get("SEARXNG_URL_EXT", "http://localhost:8080")).rstrip("/")

    def _get_crawl4ai_url(self) -> str:
        return (self.crawl4ai_url or os.environ.get("CRAWL4AI_URL_EXT", "http://localhost:8002")).rstrip("/")

    def _get_crawl4ai_token(self) -> str | None:
        return self.crawl4ai_api_token or os.environ.get("CRAWL4AI_API_TOKEN")

    def _get_crawl4ai_headers(self) -> dict:
        headers = {}
        token = self._get_crawl4ai_token()
        if token:
            headers["x-api-key"] = token
        return headers


    # -------------------------------------------------------------------------
    # search() — SearXNG JSON API
    # -------------------------------------------------------------------------

    async def search(
        self,
        query: str,
        topn: int,
        session: ClientSession,
    ) -> PageContents:
        searxng_base = self._get_searxng_url()
        params = {
            "q": query,
            "format": "json",
            # "categories": "general",
            # "language": "fr",
            "pageno": 1,
        }

        _search = with_retries(
            self._searxng_get,
            num_retries=self.num_retries,
            max_wait_time=self.max_wait_time,
        )

        try:
            data = await _search(session=session, url=f"{searxng_base}/search", params=params)
        except Exception as e:
            raise BackendError(f"SearXNG search failed for '{query}': {e}") from e

        results = data.get("results", [])[:topn]

        html_page = f"""
        <html><body>
        <h1>Search Results</h1>
        <ul>
        {"".join([f"<li><a href='{line_result["url"]}'>{line_result["title"]}</a> {line_result["content"]}</li>" for line_result in results])}
        </ul>
        </body></html>
        """

        ret = process_html(
            html=html_page,
            url="",
            title=query,
            display_urls=True,
            session=session,
        )
        logger.info(ret)
        return ret
        # return process_search_results(results, query)

    async def _searxng_get(
        self,
        session: ClientSession,
        url: str,
        params: dict,
    ) -> dict:
        async with session.get(
            url,
            params=params,
            timeout=ClientTimeout(total=15),
        ) as resp:
            if resp.status != 200:
                raise BackendError(f"SearXNG returned HTTP {resp.status}: {await resp.text()}")
            return await resp.json()

    # -------------------------------------------------------------------------
    # fetch() — Crawl4AI /scrape (markdown-first)
    # -------------------------------------------------------------------------

    async def fetch(self, url: str, session: ClientSession) -> PageContents:
        is_view_source = url.startswith(VIEW_SOURCE_PREFIX)
        if is_view_source:
            url = url[len(VIEW_SOURCE_PREFIX):]

        crawl4ai_base = self._get_crawl4ai_url()
        payload = {
            "url": url,
            "formats": ["markdown", "html"],
            "timeout": self.fetch_timeout,
        }

        _fetch = with_retries(
            self._crawl4ai_post,
            num_retries=self.num_retries,
            max_wait_time=self.max_wait_time,
        )
        data = await _fetch(session=session, endpoint=f"{crawl4ai_base}/scrape", payload=payload)

        if not data.get("success"):
            raise BackendError(f"Crawl4AI failure for '{url}': {data.get('error', 'unknown')}")

        content = data.get("data", {})
        title = content.get("metadata", {}).get("title", "")

        # view_source or no markdown → HTML pipeline
        if is_view_source or not content.get("markdown"):
            html = content.get("html", "")
            if not html:
                raise BackendError(f"No content returned for {url}")
            return process_html(html=html, url=url, title=title, display_urls=True, session=session)

        # Default: markdown pipeline
        return process_markdown(markdown=content["markdown"], url=url, title=title)

    async def _crawl4ai_post(
        self,
        session: ClientSession,
        endpoint: str,
        payload: dict,
    ) -> dict:
        async with session.post(
            endpoint,
            json=payload,
            timeout=ClientTimeout(total=self.fetch_timeout / 1000 + 5),
            headers=self._get_crawl4ai_headers(),
        ) as resp:
            if resp.status != 200:
                raise BackendError(f"Crawl4AI returned HTTP {resp.status}: {await resp.text()}")
            return await resp.json()
