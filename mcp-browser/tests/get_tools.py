# tests/get_tools.py
"""
Integration test using mcp SDK.
Run: python tests/get_tools.py
Requires: docker compose up -d
"""

import asyncio
from mcp.client.sse import sse_client
from mcp import ClientSession

MCP_URL = "http://localhost:8003/sse"


async def main():
    async with sse_client(MCP_URL) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # 1. List tools
            print("📋 Tools disponibles:")
            tools = await session.list_tools()
            for t in tools.tools:
                print(f"  - {t.name}: {t.description[:60]}")

            # 2. Search
            print("\n🔍 Search 'Python MCP protocol':")
            result = await session.call_tool("search", {"query": "Python MCP protocol"})
            print(result.content[0].text[:1000])

            # 3. Open first result
            print("\n🌐 Open result id=1:")
            result = await session.call_tool("open", {"id": "1"})
            print(result.content[0].text[:1500])

            # 4. Find in page
            print("\n🔎 Find 'protocol':")
            result = await session.call_tool("find", {"pattern": "protocol"})
            print(result.content[0].text[:500])

            print("\n✅ Done")


if __name__ == "__main__":
    asyncio.run(main())
