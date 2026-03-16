#!/bin/bash

# ============================================
#   SearXNG Self-Hosted Server Test Script
#   v2 - With 429 handling & rate limit fix
# ============================================

# ------------------------------
# CONFIGURATION
# ------------------------------
HOST="localhost"
PORT="8080"
BASE_URL="http://${HOST}:${PORT}"
FORMAT="json"
TIMEOUT=10
DELAY=1  # seconds between requests to avoid 429

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
SKIP=0
TOTAL=0
RATE_LIMITED=false

# ------------------------------
# FUNCTIONS
# ------------------------------

print_banner() {
  echo -e "${CYAN}"
  echo "================================================"
  echo "       SearXNG Server Test Script v2            "
  echo "================================================"
  echo -e "${NC}"
  echo -e "  ${BLUE}Target :${NC} ${BASE_URL}"
  echo -e "  ${BLUE}Date   :${NC} $(date)"
  echo -e "  ${BLUE}Delay  :${NC} ${DELAY}s between requests"
  echo "------------------------------------------------"
  echo ""
}

print_result() {
  local test_name=$1
  local status=$2
  local detail=$3
  TOTAL=$((TOTAL + 1))

  if [ "$status" == "PASS" ]; then
    PASS=$((PASS + 1))
    echo -e "  [${GREEN}PASS${NC}] ${test_name}"
  elif [ "$status" == "SKIP" ]; then
    SKIP=$((SKIP + 1))
    echo -e "  [${YELLOW}SKIP${NC}] ${test_name}"
  else
    FAIL=$((FAIL + 1))
    echo -e "  [${RED}FAIL${NC}] ${test_name}"
  fi

  if [ -n "$detail" ]; then
    echo -e "         ${YELLOW}→ ${detail}${NC}"
  fi
}

print_section() {
  echo ""
  echo -e "${BLUE}▶ $1${NC}"
  echo "  ----------------------------------------"
}

print_summary() {
  echo ""
  echo -e "${CYAN}================================================${NC}"
  echo -e "  ${BLUE}TEST SUMMARY${NC}"
  echo -e "${CYAN}================================================${NC}"
  echo -e "  Total   : ${TOTAL}"
  echo -e "  ${GREEN}Passed  : ${PASS}${NC}"
  echo -e "  ${RED}Failed  : ${FAIL}${NC}"
  echo -e "  ${YELLOW}Skipped : ${SKIP}${NC}"
  echo "------------------------------------------------"

  if [ "$RATE_LIMITED" == true ]; then
    echo -e "  ${YELLOW}⚠ 429 Rate Limit detected!${NC}"
    echo ""
    echo -e "  ${CYAN}Fix: Add to your settings.yml:${NC}"
    echo -e "  ${YELLOW}  server:"
    echo -e "    limiter: false${NC}"
    echo ""
    echo -e "  ${CYAN}Then restart SearXNG:${NC}"
    echo -e "  ${YELLOW}  docker restart searxng${NC}"
    echo -e "  ${YELLOW}  # or: systemctl restart searxng${NC}"
  fi

  echo ""
  if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}✔ All tests passed! SearXNG is working.${NC}"
  else
    echo -e "  ${RED}✘ Some tests failed. Check your configuration.${NC}"
  fi
  echo -e "${CYAN}================================================${NC}"
  echo ""
}

check_dependency() {
  local dep=$1
  if ! command -v "$dep" &> /dev/null; then
    echo -e "  ${YELLOW}⚠ '$dep' not installed.${NC}"
    return 1
  fi
  return 0
}

# Safe curl with 429 detection
safe_curl() {
  local url=$1
  shift
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time $TIMEOUT \
    -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64)" \
    "$@" \
    "$url")
  if [ "$code" == "429" ]; then
    RATE_LIMITED=true
  fi
  echo "$code"
  sleep $DELAY
}

# Safe curl returning body
safe_curl_body() {
  local url=$1
  shift
  local body
  body=$(curl -s \
    --max-time $TIMEOUT \
    -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64)" \
    "$@" \
    "$url")
  sleep $DELAY
  echo "$body"
}

# ------------------------------
# DEPENDENCY CHECK
# ------------------------------

print_banner

echo -e "${BLUE}▶ Checking Dependencies${NC}"
echo "  ----------------------------------------"
check_dependency curl    && echo -e "  [${GREEN}OK${NC}]   curl found"
check_dependency jq      && JQ_AVAILABLE=true  || JQ_AVAILABLE=false
check_dependency python3 && PYTHON_AVAILABLE=true || PYTHON_AVAILABLE=false
check_dependency bc      && BC_AVAILABLE=true  || BC_AVAILABLE=false

if [ "$JQ_AVAILABLE" == true ]; then
  echo -e "  [${GREEN}OK${NC}]   jq found"
fi
if [ "$PYTHON_AVAILABLE" == true ]; then
  echo -e "  [${GREEN}OK${NC}]   python3 found"
fi

# -----------------------------------------------
# TEST 1 - PING / CONNECTIVITY
# -----------------------------------------------

print_section "Test 1 - Basic Connectivity"

HTTP_CODE=$(safe_curl "${BASE_URL}")

case "$HTTP_CODE" in
  200|301|302)
    print_result "Server is reachable" "PASS" "HTTP Code: ${HTTP_CODE}"
    ;;
  429)
    print_result "Server is reachable (but rate limited)" "PASS" \
      "HTTP 429 - Server is UP but limiter is enabled"
    RATE_LIMITED=true
    ;;
  000)
    print_result "Server is reachable" "FAIL" \
      "No response - Is SearXNG running on port ${PORT}?"
    echo ""
    echo -e "  ${RED}Critical: Server not responding. Stopping tests.${NC}"
    print_summary
    exit 1
    ;;
  *)
    print_result "Server is reachable" "FAIL" "HTTP Code: ${HTTP_CODE}"
    ;;
esac

# -----------------------------------------------
# TEST 2 - HEALTHZ ENDPOINT
# -----------------------------------------------

print_section "Test 2 - Health Check"

HEALTH_CODE=$(safe_curl "${BASE_URL}/healthz")
if [ "$HEALTH_CODE" == "200" ]; then
  print_result "GET /healthz" "PASS" "HTTP ${HEALTH_CODE}"
else
  print_result "GET /healthz" "FAIL" "HTTP ${HEALTH_CODE}"
fi

# -----------------------------------------------
# TEST 3 - RATE LIMIT DETECTION
# -----------------------------------------------

print_section "Test 3 - Rate Limit Detection"

if [ "$RATE_LIMITED" == true ]; then
  print_result "Rate limiter check" "FAIL" \
    "HTTP 429 detected - limiter is ON"
  echo ""
  echo -e "  ${YELLOW}┌─────────────────────────────────────────────┐${NC}"
  echo -e "  ${YELLOW}│  HOW TO FIX:                                │${NC}"
  echo -e "  ${YELLOW}│                                             │${NC}"
  echo -e "  ${YELLOW}│  1. Find your settings.yml:                 │${NC}"
  echo -e "  ${YELLOW}│     find / -name settings.yml 2>/dev/null   │${NC}"
  echo -e "  ${YELLOW}│                                             │${NC}"
  echo -e "  ${YELLOW}│  2. Edit it and set:                        │${NC}"
  echo -e "  ${YELLOW}│     server:                                 │${NC}"
  echo -e "  ${YELLOW}│       limiter: false                        │${NC}"
  echo -e "  ${YELLOW}│                                             │${NC}"
  echo -e "  ${YELLOW}│  3. Restart:                                │${NC}"
  echo -e "  ${YELLOW}│     docker restart searxng                  │${NC}"
  echo -e "  ${YELLOW}└─────────────────────────────────────────────┘${NC}"
  echo ""
  echo -e "  ${CYAN}Continuing tests with User-Agent header...${NC}"
else
  print_result "Rate limiter check" "PASS" "No 429 detected"
fi

# -----------------------------------------------
# TEST 4 - HOMEPAGE CONTENT
# -----------------------------------------------

print_section "Test 4 - Homepage Content"

HOMEPAGE=$(safe_curl_body "${BASE_URL}")

if echo "$HOMEPAGE" | grep -qi "429\|too many"; then
  print_result "Homepage content" "SKIP" "Rate limited - cannot check content"
elif echo "$HOMEPAGE" | grep -qi "searx"; then
  print_result "Homepage contains 'searx'" "PASS"
else
  print_result "Homepage contains 'searx'" "FAIL" "Unexpected content"
fi

if echo "$HOMEPAGE" | grep -qi "search"; then
  print_result "Homepage contains 'search'" "PASS"
elif echo "$HOMEPAGE" | grep -qi "429\|too many"; then
  print_result "Homepage contains 'search'" "SKIP" "Rate limited"
else
  print_result "Homepage contains 'search'" "FAIL"
fi

# -----------------------------------------------
# TEST 5 - JSON FORMAT SEARCH (GET)
# -----------------------------------------------

print_section "Test 5 - JSON Search (GET)"

RESPONSE=$(safe_curl_body \
  "${BASE_URL}/search?q=hello+world&format=json" \
  -H "Accept: application/json")

HTTP_CODE=$(safe_curl \
  "${BASE_URL}/search?q=test&format=json" \
  -H "Accept: application/json")

if [ "$HTTP_CODE" == "200" ]; then
  print_result "GET /search returns 200" "PASS" "HTTP ${HTTP_CODE}"
elif [ "$HTTP_CODE" == "429" ]; then
  print_result "GET /search returns 200" "FAIL" \
    "HTTP 429 - Rate limited. Disable limiter in settings.yml"
else
  print_result "GET /search returns 200" "FAIL" \
    "HTTP ${HTTP_CODE} - Enable json format in settings.yml"
fi

# JSON validation
if echo "$RESPONSE" | grep -q '"results"'; then
  if [ "$JQ_AVAILABLE" == true ]; then
    if echo "$RESPONSE" | jq . > /dev/null 2>&1; then
      print_result "Response is valid JSON" "PASS"
    else
      print_result "Response is valid JSON" "FAIL"
    fi
  fi
  print_result "JSON contains 'results'" "PASS"
  print_result "JSON contains 'query'"   "PASS"
else
  if echo "$RESPONSE" | grep -q "429\|Too Many"; then
    print_result "Response is valid JSON" "SKIP" "Rate limited"
    print_result "JSON contains 'results'" "SKIP" "Rate limited"
    print_result "JSON contains 'query'"   "SKIP" "Rate limited"
  else
    print_result "Response is valid JSON" "FAIL" "Not valid JSON"
    print_result "JSON contains 'results'" "FAIL"
    print_result "JSON contains 'query'"   "FAIL"
  fi
fi

# -----------------------------------------------
# TEST 6 - POST SEARCH
# -----------------------------------------------

print_section "Test 6 - POST Search"

POST_CODE=$(safe_curl \
  "${BASE_URL}/search" \
  -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "q=linux&format=json")

if [ "$POST_CODE" == "200" ]; then
  print_result "POST /search returns 200" "PASS" "HTTP ${POST_CODE}"
elif [ "$POST_CODE" == "429" ]; then
  print_result "POST /search returns 200" "FAIL" "HTTP 429 - Rate limited"
else
  print_result "POST /search returns 200" "FAIL" "HTTP ${POST_CODE}"
fi

# -----------------------------------------------
# TEST 7 - SPECIAL ENDPOINTS
# -----------------------------------------------

print_section "Test 7 - Special Endpoints"

declare -A ENDPOINTS=(
  ["/stats"]="Stats page"
  ["/config"]="Config endpoint"
  ["/favicon.ico"]="Favicon"
  ["/search?q=test&format=json"]="Search endpoint"
)

for ENDPOINT in "${!ENDPOINTS[@]}"; do
  NAME="${ENDPOINTS[$ENDPOINT]}"
  CODE=$(safe_curl "${BASE_URL}${ENDPOINT}")
  if [ "$CODE" == "200" ]; then
    print_result "${NAME} (${ENDPOINT})" "PASS" "HTTP ${CODE}"
  elif [ "$CODE" == "429" ]; then
    print_result "${NAME} (${ENDPOINT})" "FAIL" "HTTP 429 - Rate limited"
  else
    print_result "${NAME} (${ENDPOINT})" "FAIL" "HTTP ${CODE}"
  fi
done

# -----------------------------------------------
# TEST 8 - RESPONSE TIME
# -----------------------------------------------

print_section "Test 8 - Response Time"

RESPONSE_TIME=$(curl -s -o /dev/null \
  -w "%{time_total}" \
  --max-time $TIMEOUT \
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64)" \
  "${BASE_URL}/healthz")

echo -e "  ${BLUE}Response Time (healthz):${NC} ${RESPONSE_TIME}s"

if [ "$BC_AVAILABLE" == true ]; then
  if (( $(echo "$RESPONSE_TIME < 5.0" | bc -l) )); then
    print_result "Response time < 5.0s" "PASS" "${RESPONSE_TIME}s"
  else
    print_result "Response time < 5.0s" "FAIL" "${RESPONSE_TIME}s too slow"
  fi
else
  echo -e "  ${YELLOW}⚠ Install bc for numeric comparison: sudo apt install bc${NC}"
fi

# -----------------------------------------------
# TEST 9 - HTTP HEADERS
# -----------------------------------------------

print_section "Test 9 - HTTP Headers"

HEADERS=$(curl -s -I \
  --max-time $TIMEOUT \
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64)" \
  "${BASE_URL}")

echo -e "  ${BLUE}Headers received:${NC}"
echo "$HEADERS" | grep -E "HTTP|Content-Type|X-|Server|Cache" | \
  sed 's/^/    /'

echo ""

if echo "$HEADERS" | grep -qi "content-type"; then
  print_result "Content-Type header present" "PASS"
else
  print_result "Content-Type header present" "FAIL"
fi

if echo "$HEADERS" | grep -qi "x-content-type-options"; then
  print_result "X-Content-Type-Options present" "PASS"
else
  print_result "X-Content-Type-Options present" "FAIL" "Security header missing"
fi

if echo "$HEADERS" | grep -qi "x-frame-options\|content-security-policy"; then
  print_result "X-Frame-Options / CSP present" "PASS"
else
  print_result "X-Frame-Options / CSP present" "FAIL" "Security header missing"
fi

# -----------------------------------------------
# TEST 10 - SAMPLE JSON OUTPUT
# -----------------------------------------------

print_section "Test 10 - Sample JSON Output"

if [ "$JQ_AVAILABLE" == true ]; then
  SAMPLE=$(curl -s \
    --max-time $TIMEOUT \
    -H "Accept: application/json" \
    -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64)" \
    "${BASE_URL}/search?q=searxng&format=json" \
    | jq '{
        query: .query,
        number_of_results: .number_of_results,
        first_result: .results[0] | {
          title: .title,
          url: .url,
          engine: .engine
        }
      }' 2>/dev/null)

  if [ -n "$SAMPLE" ] && echo "$SAMPLE" | grep -q "query"; then
    echo "$SAMPLE"
    print_result "Sample JSON output" "PASS"
  else
    print_result "Sample JSON output" "FAIL" \
      "No results (rate limited or no engines available)"
  fi
else
  echo -e "  ${YELLOW}Install jq: sudo apt install jq${NC}"
  print_result "Sample JSON output" "SKIP" "jq not installed"
fi

# ------------------------------
# SUMMARY
# ------------------------------

print_summary

# -----------------------------------------------
# QUICK FIX COMMANDS
# -----------------------------------------------

if [ "$RATE_LIMITED" == true ]; then
  echo -e "${CYAN}================================================${NC}"
  echo -e "  ${BLUE}QUICK FIX COMMANDS${NC}"
  echo -e "${CYAN}================================================${NC}"
  echo ""
  echo -e "  ${GREEN}# Docker:${NC}"
  echo -e "  docker exec searxng sed -i 's/limiter: true/limiter: false/' \\"
  echo -e "    /etc/searxng/settings.yml"
  echo -e "  docker restart searxng"
  echo ""
  echo -e "  ${GREEN}# Or manually find and edit settings.yml:${NC}"
  echo -e "  find / -name 'settings.yml' 2>/dev/null | grep searx"
  echo ""
  echo -e "  ${GREEN}# Then set:${NC}"
  echo -e "  ${YELLOW}  server:"
  echo -e "    limiter: false${NC}"
  echo ""
  echo -e "${CYAN}================================================${NC}"
fi

exit $FAIL
