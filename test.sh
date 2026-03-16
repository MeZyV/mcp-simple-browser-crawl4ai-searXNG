#!/bin/bash

MCP_URL="http://localhost:8003"
SSE_LOG=$(mktemp)

# 1. Connect to SSE in background
curl -s -N "${MCP_URL}/sse" > "$SSE_LOG" &
SSE_PID=$!
sleep 2

# 2. Parse the message endpoint - strip all control characters
MSG_ENDPOINT=$(grep -m1 "^data:" "$SSE_LOG" | sed 's/^data: *//' | tr -d '\r\n\t ')
MSG_ENDPOINT="${MCP_URL}${MSG_ENDPOINT}"
echo "Message endpoint: [$MSG_ENDPOINT]"

# 3. Initialize
echo ""
echo "--- Initializing ---"
curl -s -v --post301 "$MSG_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"bash-client","version":"1.0.0"}}}' 2>&1
sleep 3

echo ""
echo "--- SSE after init ---"
cat "$SSE_LOG"

# 4. Notify initialized
curl -s "$MSG_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' 2>&1
sleep 1

# 5. List tools
echo ""
echo "--- Listing Tools ---"
curl -s -v "$MSG_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' 2>&1
sleep 3

# 6. Call search tool
QUERY="latest news about AI"
echo ""
echo "--- Searching: $QUERY ---"
curl -s "$MSG_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"search\",\"arguments\":{\"query\":\"$QUERY\",\"topn\":5}}}"
sleep 5

# 7. Show results
echo ""
echo "--- Search Results ---"
grep "^data:" "$SSE_LOG" | tail -n +2 | while read -r line; do
  echo "$line" | sed 's/^data: //' | jq . 2>/dev/null
done

# 8. Final SSE dump
echo ""
echo "--- Final SSE channel ---"
cat "$SSE_LOG"

# Cleanup
kill $SSE_PID 2>/dev/null
rm "$SSE_LOG"
