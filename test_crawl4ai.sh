#!/bin/bash

HOST="localhost"
PORT="8002"
BASE_URL="http://${HOST}:${PORT}"
TIMEOUT=30

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

print_section() { echo -e "\n${BLUE}--- $1 ---${NC}"; }
print_pass() { echo -e "  [${GREEN}PASS${NC}] $1 ${CYAN}$2${NC}"; ((PASS++)); }
print_fail() { echo -e "  [${RED}FAIL${NC}] $1 ${YELLOW}$2${NC}"; ((FAIL++)); }

check() {
  local label=$1
  local response=$2
  local expect_key=$3
  local expect_val=$4
  local http_code=$5

  if [[ "$http_code" == "200" ]] && echo "$response" | grep -q "\"${expect_key}\".*${expect_val}"; then
    local info=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.keys())[:4])" 2>/dev/null)
    print_pass "$label" "HTTP $http_code | $info"
  else
    local err=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('detail','?'))" 2>/dev/null)
    print_fail "$label" "HTTP $http_code | $err"
  fi
}

# ─────────────────────────────────────────
print_section "Test 1 - Health Check"
# ─────────────────────────────────────────
RES=$(curl -s -o /tmp/body.json -w "%{http_code}" "${BASE_URL}/health")
BODY=$(cat /tmp/body.json)
if [[ "$RES" == "200" ]] && echo "$BODY" | grep -q "ok\|healthy\|true"; then
  print_pass "GET /health" "HTTP $RES | $(echo $BODY | tr -d ' \n')"
else
  print_fail "GET /health" "HTTP $RES | $BODY"
fi

# ─────────────────────────────────────────
print_section "Test 2 - Scrape simple URL"
# ─────────────────────────────────────────
RES=$(curl -s -o /tmp/body.json -w "%{http_code}" -X POST "${BASE_URL}/scrape" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}')
BODY=$(cat /tmp/body.json)
if [[ "$RES" == "200" ]] && echo "$BODY" | grep -q '"success":.*true'; then
  TITLE=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['metadata']['title'])" 2>/dev/null)
  WORDS=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['metadata']['word_count'])" 2>/dev/null)
  print_pass "POST /scrape" "HTTP $RES | title: $TITLE | words: $WORDS"
else
  print_fail "POST /scrape" "HTTP $RES | $(echo $BODY | head -c 100)"
fi

# ─────────────────────────────────────────
print_section "Test 3 - Scrape markdown content"
# ─────────────────────────────────────────
RES=$(curl -s -o /tmp/body.json -w "%{http_code}" -X POST "${BASE_URL}/scrape" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://httpbin.org/html"}')
BODY=$(cat /tmp/body.json)
if [[ "$RES" == "200" ]] && echo "$BODY" | grep -q '"markdown"'; then
  MD_LEN=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['data']['markdown']))" 2>/dev/null)
  print_pass "POST /scrape (httpbin)" "HTTP $RES | markdown length: $MD_LEN chars"
else
  print_fail "POST /scrape (httpbin)" "HTTP $RES | $(echo $BODY | head -c 100)"
fi

# ─────────────────────────────────────────
print_section "Test 4 - Batch Scrape"
# ─────────────────────────────────────────
RES=$(curl -s -o /tmp/body.json -w "%{http_code}" -X POST "${BASE_URL}/batch-scrape" \
  -H "Content-Type: application/json" \
  -d '{"urls": ["https://example.com", "https://httpbin.org/html"]}')
BODY=$(cat /tmp/body.json)
if [[ "$RES" == "200" ]]; then
  COUNT=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else d.get('count','?'))" 2>/dev/null)
  print_pass "POST /batch-scrape" "HTTP $RES | results: $COUNT"
else
  print_fail "POST /batch-scrape" "HTTP $RES | $(echo $BODY | head -c 100)"
fi

# ─────────────────────────────────────────
print_section "Test 5 - Extract"
# ─────────────────────────────────────────
RES=$(curl -s -o /tmp/body.json -w "%{http_code}" -X POST "${BASE_URL}/extract" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com", "extraction_type": "css", "selector": "h1"}')
BODY=$(cat /tmp/body.json)
if [[ "$RES" == "200" ]]; then
  print_pass "POST /extract" "HTTP $RES | $(echo $BODY | python3 -c 'import sys,json; d=json.load(sys.stdin); print(str(d)[:80])' 2>/dev/null)"
else
  print_fail "POST /extract" "HTTP $RES | $(echo $BODY | head -c 100)"
fi

# ─────────────────────────────────────────
print_section "Test 6 - Invalid URL (error handling)"
# ─────────────────────────────────────────
RES=$(curl -s -o /tmp/body.json -w "%{http_code}" -X POST "${BASE_URL}/scrape" \
  -H "Content-Type: application/json" \
  -d '{"url": "not-a-valid-url"}')
BODY=$(cat /tmp/body.json)
if [[ "$RES" != "200" ]] || echo "$BODY" | grep -q '"success":.*false\|error\|detail'; then
  print_pass "POST /scrape (invalid URL)" "HTTP $RES | error handled correctly"
else
  print_fail "POST /scrape (invalid URL)" "HTTP $RES | expected error, got success"
fi

# ─────────────────────────────────────────
print_section "Test 7 - Missing body (422)"
# ─────────────────────────────────────────
RES=$(curl -s -o /tmp/body.json -w "%{http_code}" -X POST "${BASE_URL}/scrape" \
  -H "Content-Type: application/json" \
  -d '{}')
BODY=$(cat /tmp/body.json)
if [[ "$RES" == "422" ]]; then
  print_pass "POST /scrape (empty body)" "HTTP $RES | validation error as expected"
else
  print_fail "POST /scrape (empty body)" "HTTP $RES | expected 422"
fi

# ─────────────────────────────────────────
echo -e "\n${BLUE}======================================${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}  |  ${RED}FAIL: $FAIL${NC}  |  TOTAL: $((PASS + FAIL))"
echo -e "${BLUE}======================================${NC}\n"
SCRIPT

chmod +x /tmp/test_crawl4ai.sh
/tmp/test_crawl4ai.sh
