#!/bin/bash
# ============================================================
# Register the pipe function in Open WebUI
# Run ONCE after first startup + account creation
# ============================================================
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
OPEN_WEBUI_URL="${1:-http://localhost:8080}"

echo "========================================="
echo "  Register Pipe Function"
echo "========================================="
echo ""

# Check Open WebUI
if ! curl -s "$OPEN_WEBUI_URL" > /dev/null 2>&1; then
    echo "ERROR: Open WebUI not running at $OPEN_WEBUI_URL"
    echo "Run ./start.sh first"
    exit 1
fi

# Get credentials
if [ -f "$BASE_DIR/.token" ]; then
    TOKEN=$(cat "$BASE_DIR/.token")
    echo "Using saved token."
else
    echo "No saved token. Please provide credentials."
    echo ""
    read -p "  Email: " EMAIL
    read -s -p "  Password: " PASSWORD
    echo ""

    RESP=$(curl -s -X POST "$OPEN_WEBUI_URL/api/v1/auths/signup" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"Admin\", \"email\": \"$EMAIL\", \"password\": \"$PASSWORD\"}")

    TOKEN=$(echo "$RESP" | python3.11 -c "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)

    if [ -z "$TOKEN" ]; then
        echo "Signup failed (account may exist). Trying login..."
        RESP=$(curl -s -X POST "$OPEN_WEBUI_URL/api/v1/auths/signin" \
            -H "Content-Type: application/json" \
            -d "{\"email\": \"$EMAIL\", \"password\": \"$PASSWORD\"}")
        TOKEN=$(echo "$RESP" | python3.11 -c "import json,sys; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
    fi

    if [ -z "$TOKEN" ]; then
        echo "ERROR: Could not authenticate."
        exit 1
    fi

    echo "$TOKEN" > "$BASE_DIR/.token"
    echo "  Authenticated."
fi

# Register pipe
PIPE_FILE="$BASE_DIR/github_pipe.py"

echo ""
echo "Registering pipe..."

python3.11 << PYEOF
import requests, json

token = open("$BASE_DIR/.token").read().strip()
code = open("$PIPE_FILE").read()
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
base = "$OPEN_WEBUI_URL"

resp = requests.post(f"{base}/api/v1/functions/create", headers=headers, json={
    "id": "github_mcp_agent",
    "name": "GitHub MCP Agent",
    "type": "pipe",
    "content": code,
    "meta": {"description": "v0.4.0 — Direct GitHub API for table/chart, model+MCP for general queries"}
})

if resp.status_code == 200:
    print(f"  Created: {resp.json()['name']}")
elif resp.status_code == 400:
    resp = requests.post(f"{base}/api/v1/functions/id/github_mcp_agent/update", headers=headers, json={
        "id": "github_mcp_agent", "name": "GitHub MCP Agent", "type": "pipe",
        "content": code, "meta": {"description": "v0.4.0 updated"}
    })
    print(f"  Updated: {resp.status_code}")
else:
    print(f"  Error: {resp.status_code} {resp.text[:200]}")

resp = requests.post(f"{base}/api/v1/functions/id/github_mcp_agent/toggle", headers=headers)
print(f"  Active: {resp.json().get('is_active')}")

try:
    mcpo_cfg = json.load(open("$BASE_DIR/mcpo/config.json"))
    for server in mcpo_cfg.get("mcpServers", {}).values():
        for key, val in server.get("env", {}).items():
            if "TOKEN" in key or "PAT" in key:
                resp = requests.post(f"{base}/api/v1/functions/id/github_mcp_agent/valves/update",
                    headers=headers, json={"GITHUB_TOKEN": val})
                print(f"  GITHUB_TOKEN set from mcpo config")
                break
except:
    print("  Note: Set GITHUB_TOKEN manually in Open WebUI > Functions > Valves")
PYEOF

echo ""
echo "Done! Open $OPEN_WEBUI_URL and select 'GitHub MCP Agent' model."
