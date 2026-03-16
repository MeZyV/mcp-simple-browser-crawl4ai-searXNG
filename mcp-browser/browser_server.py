import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from typing import Union, Optional

import uvicorn
from mcp.server.fastmcp import Context, FastMCP
from tools.simple_browser import SimpleBrowserTool
from tools.simple_browser.backend import SearxngCrawlBackend
from starlette.middleware.cors import CORSMiddleware

@dataclass
class AppContext:
    browsers: dict[str, SimpleBrowserTool] = field(default_factory=dict)

    def create_or_get_browser(self, session_id: str) -> SimpleBrowserTool:
        if session_id not in self.browsers:
            # tool_backend = os.getenv("BROWSER_BACKEND", "exa")
            # if tool_backend == "youcom":
            #     backend = YouComBackend(source="web")
            # elif tool_backend == "exa":
            #     backend = ExaBackend(source="web")
            # else:
            #     raise ValueError(f"Invalid tool backend: {tool_backend}")
            backend = SearxngCrawlBackend(source="web")
            self.browsers[session_id] = SimpleBrowserTool(backend=backend)
        return self.browsers[session_id]

    def remove_browser(self, session_id: str) -> None:
        self.browsers.pop(session_id, None)


@asynccontextmanager
async def app_lifespan(_server: FastMCP) -> AsyncIterator[AppContext]:
    yield AppContext()


PORT = int(os.getenv("MCP_BROWSER_PORT", 8003))
HOST = os.getenv("MCP_BROWSER_HOST", "0.0.0.0")
# Allowed origins - customize as needed
ALLOWED_ORIGINS = os.getenv(
    "CORS_ORIGINS",
    "*"  # or "http://localhost:3000,http://host.docker.internal:3000"
).split(",")

# Pass lifespan to server
mcp = FastMCP(
    name="browser",
    instructions=r"""
Tool for browsing.
The `cursor` appears in brackets before each browsing display: `[{cursor}]`.
Cite information from the tool using the following format:
`【{cursor}†L{line_start}(-L{line_end})?】`, for example: `【6†L9-L11】` or `【8†L3】`. 
Do not quote more than 10 words directly from the tool output.
sources=web
""".strip(),
    lifespan=app_lifespan,
    port=PORT,
    host=HOST
)

@mcp.tool(
    name="search",
    title="Search for information",
    description=
    "Searches for information related to `query` and displays `topn` results.",
)
async def search(ctx: Context,
                 query: str,
                 topn: int = 10,
                 source: Optional[str] = None) -> str:
    """Search for information related to a query"""
    browser = ctx.request_context.lifespan_context.create_or_get_browser(
        ctx.client_id)
    messages = []
    async for message in browser.search(query=query, topn=topn, source=source):
        if message.content and hasattr(message.content[0], 'text'):
            messages.append(message.content[0].text)
    return "\n".join(messages)


@mcp.tool(
    name="open",
    title="Open a link or page",
    description="""
Opens the link `id` from the page indicated by `cursor` starting at line number `loc`, showing `num_lines` lines.
Valid link ids are displayed with the formatting: `【{id}†.*】`.
If `cursor` is not provided, the most recent page is implied.
If `id` is a string, it is treated as a fully qualified URL associated with `source`.
If `loc` is not provided, the viewport will be positioned at the beginning of the document or centered on the most relevant passage, if available.
Use this function without `id` to scroll to a new location of an opened page.
""".strip(),
)
async def open_link(ctx: Context,
                    id: Union[int, str] = -1,
                    cursor: int = -1,
                    loc: int = -1,
                    num_lines: int = -1,
                    view_source: bool = False,
                    source: Optional[str] = None) -> str:
    """Open a link or navigate to a page location"""
    browser = ctx.request_context.lifespan_context.create_or_get_browser(
        ctx.client_id)
    messages = []
    async for message in browser.open(id=id,
                                      cursor=cursor,
                                      loc=loc,
                                      num_lines=num_lines,
                                      view_source=view_source,
                                      source=source):
        if message.content and hasattr(message.content[0], 'text'):
            messages.append(message.content[0].text)
    return "\n".join(messages)


@mcp.tool(
    name="find",
    title="Find pattern in page",
    description=
    "Finds exact matches of `pattern` in the current page, or the page given by `cursor`.",
)
async def find_pattern(ctx: Context, pattern: str, cursor: int = -1) -> str:
    """Find exact matches of a pattern in the current page"""
    browser = ctx.request_context.lifespan_context.create_or_get_browser(
        ctx.client_id)
    messages = []
    async for message in browser.find(pattern=pattern, cursor=cursor):
        if message.content and hasattr(message.content[0], 'text'):
            messages.append(message.content[0].text)
    return "\n".join(messages)


if __name__ == "__main__":
    # ── Get the underlying ASGI app from FastMCP ──────────────────────────────
    # Read from your environment variables, with fallback defaults
    # transport_type = os.getenv("MCP_TRANSPORT", "sse")
    # server_port = int(os.getenv("MCP_BROWSER_PORT", 8003))
    # server_host = os.getenv("MCP_BROWSER_HOST", "0.0.0.0")
    try:
        asgi_app = mcp.sse_app()          # older fastmcp versions
    except AttributeError:
        asgi_app = mcp.http_app()         # fallback

    # ── Wrap with CORS middleware ─────────────────────────────────────────────
    asgi_app = CORSMiddleware(
        asgi_app,
        allow_origins=ALLOWED_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["*"],
    )

    # ── Run with uvicorn directly ─────────────────────────────────────────────
    uvicorn.run(asgi_app, host=HOST, port=PORT)
