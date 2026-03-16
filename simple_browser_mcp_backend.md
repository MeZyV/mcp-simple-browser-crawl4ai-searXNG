# Simple Browser MCP Backend (SearXNG + Crawl4AI)

This document provides a minimal implementation derived from the GPT‑OSS simple browser tool but replacing the search backend with SearXNG and the page fetch backend with Crawl4AI.

Directory structure:

```
simple-browser-mcp/

app/
 ├─ main.py
 ├─ browser_state.py
 ├─ browser_backend.py
 ├─ tools.py
 ├─ searxng_client.py
 ├─ crawl4ai_client.py

Dockerfile
requirements.txt
docker-compose.yml
```

---

# requirements.txt

```
fastapi
uvicorn
httpx
pydantic
sse-starlette
```

---

# browser_state.py

```python
class BrowserState:

    def __init__(self):
        self.current_url = None
        self.page_text = ""
        self.search_results = []


browser_state = BrowserState()
```

---

# searxng_client.py

```python
import httpx

SEARXNG_URL_EXT = "http://searxng:8080"


async def search(query: str, k: int = 5):

    async with httpx.AsyncClient() as client:

        r = await client.get(
            f"{SEARXNG_URL_EXT}/search",
            params={
                "q": query,
                "format": "json"
            }
        )

    data = r.json()

    results = []

    for item in data.get("results", [])[:k]:

        results.append(
            {
                "title": item.get("title"),
                "url": item.get("url"),
                "snippet": item.get("content")
            }
        )

    return results
```

---

# crawl4ai_client.py

```python
import httpx

CRAWL4AI_URL_EXT = "http://crawl4ai:8002"


async def open_page(url: str):

    payload = {"url": url}

    async with httpx.AsyncClient(timeout=60) as client:

        r = await client.post(
            f"{CRAWL4AI_URL_EXT}/crawl",
            json=payload
        )

    data = r.json()

    text = data.get("markdown") or data.get("text")

    return text
```

---

# browser_backend.py

```python
from .searxng_client import search
from .crawl4ai_client import open_page
from .browser_state import browser_state


class SearxngCrawlBackend:

    async def search(self, query: str):

        results = await search(query)

        browser_state.search_results = results

        return results


    async def open(self, url: str):

        text = await open_page(url)

        browser_state.current_url = url
        browser_state.page_text = text

        return {
            "url": url,
            "length": len(text)
        }
```

---

# tools.py

```python
import re

from .browser_backend import SearxngCrawlBackend
from .browser_state import browser_state

backend = SearxngCrawlBackend()


async def search_tool(query: str):

    return await backend.search(query)


async def open_tool(url: str):

    return await backend.open(url)


async def find_tool(pattern: str, max_results: int = 20):

    text = browser_state.page_text

    matches = []

    for m in re.finditer(pattern, text, re.IGNORECASE):

        start = max(0, m.start() - 100)
        end = min(len(text), m.end() + 100)

        snippet = text[start:end]

        matches.append(snippet)

        if len(matches) >= max_results:
            break

    return matches
```

---

# main.py

```python
from fastapi import FastAPI
from sse_starlette.sse import EventSourceResponse

from .tools import search_tool, open_tool, find_tool

app = FastAPI()


@app.post("/tool/search")
async def search(query: str):

    return await search_tool(query)


@app.post("/tool/open")
async def open_page(url: str):

    return await open_tool(url)


@app.post("/tool/find")
async def find(pattern: str):

    return await find_tool(pattern)


@app.get("/sse")
async def sse():

    async def event_generator():

        yield {
            "event": "ready",
            "data": "browser ready"
        }

    return EventSourceResponse(event_generator())
```

---

# Dockerfile

```
FROM python:3.11

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8002"]
```

---

# docker-compose.yml

```
version: '3.9'

services:

  browser:
    build: .
    ports:
      - "8002:8002"
    depends_on:
      - searxng
      - crawl4ai

  searxng:
    image: searxng/searxng
    ports:
      - "8080:8080"

  crawl4ai:
    image: unclecode/crawl4ai
    ports:
      - "11235:11235"
```

---

# Run

```
docker compose up --build
```

Test:

```
curl -X POST "localhost:8002/tool/search?query=rust+language"
```

```
curl -X POST "localhost:8002/tool/open?url=https://www.rust-lang.org"
```

```
curl -X POST "localhost:8002/tool/find?pattern=Rust"
```

---

This reproduces the GPT‑OSS simple browser behavior with:

search → SearXNG
open → Crawl4AI
find → regex over cached page

while remaining lightweight and containerized.

