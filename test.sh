#!/bin/bash
# ============================================================
# Smoke Test: Verify all three output formats work correctly
# Run this after setup + start + register-pipe to validate
# ============================================================
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
OPEN_WEBUI_URL="${1:-http://localhost:8080}"
PASS=0
FAIL=0
TOTAL=3

echo "========================================="
echo "  Open WebUI + GitHub Pipe — Smoke Test"
echo "========================================="

# ── Pre-checks ────────────────────────────────────────────
echo ""
echo "Pre-checks..."

# Token
if [ ! -f "$BASE_DIR/.token" ]; then
    echo "  ERROR: No .token file found. Run ./register-pipe.sh first."
    exit 1
fi
TOKEN=$(cat "$BASE_DIR/.token")
echo "  Token: OK"

# Services
for SVC in "Ollama|http://localhost:11434" "MCPO|http://localhost:8300" "Open WebUI|$OPEN_WEBUI_URL"; do
    NAME="${SVC%%|*}"
    URL="${SVC##*|}"
    if curl -s "$URL" > /dev/null 2>&1; then
        echo "  $NAME: OK"
    else
        echo "  ERROR: $NAME not running at $URL. Run ./start.sh first."
        exit 1
    fi
done

# ── Helper function ───────────────────────────────────────
run_test() {
    local TEST_NUM="$1"
    local TEST_NAME="$2"
    local PROMPT="$3"
    local EXPECT_PATTERN="$4"
    local MAX_TIME="$5"

    echo ""
    echo "─────────────────────────────────────────"
    echo "  TEST $TEST_NUM: $TEST_NAME"
    echo "─────────────────────────────────────────"
    echo "  Prompt: \"$PROMPT\""
    echo "  Expect: pattern matching /$EXPECT_PATTERN/"
    echo ""

    START_TIME=$(date +%s)
    RESPONSE=$(curl -s -X POST "$OPEN_WEBUI_URL/api/chat/completions" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"github_mcp_agent\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"stream\":false}" \
        --max-time "$MAX_TIME" 2>&1) || true
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    # Extract content from response
    CONTENT=$(echo "$RESPONSE" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read(), strict=False)
    msg = d.get('choices', [{}])[0].get('message', {}).get('content', '')
    print(msg)
except Exception as e:
    print(f'PARSE_ERROR: {e}')
" 2>&1)

    # Check result
    if [ -z "$CONTENT" ] || echo "$CONTENT" | grep -q "PARSE_ERROR"; then
        echo "  ❌ FAIL (${ELAPSED}s) — No valid response"
        echo "  Raw: ${RESPONSE:0:200}"
        FAIL=$((FAIL + 1))
        return 1
    fi

    if echo "$CONTENT" | grep -qE "$EXPECT_PATTERN"; then
        echo "  ✅ PASS (${ELAPSED}s)"
        echo ""
        echo "  Response preview:"
        echo "  ────────────────"
        echo "$CONTENT" | head -20 | sed 's/^/  /'
        if [ "$(echo "$CONTENT" | wc -l)" -gt 20 ]; then
            echo "  ... (truncated)"
        fi
        PASS=$((PASS + 1))
        return 0
    else
        echo "  ❌ FAIL (${ELAPSED}s) — Pattern not found"
        echo ""
        echo "  Response preview:"
        echo "  ────────────────"
        echo "$CONTENT" | head -10 | sed 's/^/  /'
        FAIL=$((FAIL + 1))
        return 1
    fi
}

# ── Test 1: TABLE format (Direct GitHub API path) ─────────
run_test 1 "TABLE Format (Direct API)" \
    "Show me top 5 Python repos as table" \
    "\| # \| Repository" \
    30

# ── Test 2: PIE CHART format (Direct GitHub API path) ─────
run_test 2 "PIE CHART Format (Direct API)" \
    "Show me top 5 JavaScript repos as pie chart" \
    "mermaid|pie" \
    30

# ── Test 3: DEFAULT format (Model + MCP tool calling) ─────
run_test 3 "DEFAULT Format (Model + MCP)" \
    "What are the top 3 most starred Python repositories?" \
    "github\.com|stars|popular|public-apis|system-design" \
    120

# ── Summary ───────────────────────────────────────────────
echo ""
echo "========================================="
echo "  RESULTS: $PASS/$TOTAL passed, $FAIL/$TOTAL failed"
echo "========================================="

if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "  🎉 All tests passed! Setup is working correctly."
    echo ""
    exit 0
else
    echo ""
    echo "  ⚠️  Some tests failed. Check output above for details."
    echo ""
    echo "  Troubleshooting:"
    echo "    - Check logs:  tail -50 logs/open-webui.log"
    echo "    - Check model: curl http://localhost:11434/api/tags"
    echo "    - Check MCPO:  curl http://localhost:8300/github/openapi.json | python3 -c 'import json,sys;print(len(json.load(sys.stdin)[\"paths\"]))' "
    echo "    - Re-register: ./register-pipe.sh"
    echo ""
    exit 1
fi
