# Dockerfile.mcp-browser
FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY pyproject.toml .
RUN pip install --no-cache-dir .

# Copy source
COPY . .

EXPOSE ${MCP_BROWSER_PORT:-8003}

# CMD uvicorn gpt-oss-mcp-server/browser_server:${MCP_TRANSPORT:="sse"} --host 0.0.0.0 --port ${MCP_BROWSER_PORT:-8003}
# CMD mcp run browser_server.py --transport ${MCP_TRANSPORT:-sse}

CMD ["python", "browser_server.py"]