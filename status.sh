#!/bin/bash
# ============================================================
# Check status of all services
# ============================================================

echo "========================================="
echo "  Service Status"
echo "========================================="

for svc in ollama mcpo open-webui; do
    STATUS=$(sudo systemctl is-active $svc 2>/dev/null || echo "not found")
    printf "  %-12s %s\n" "$svc:" "$STATUS"
done

echo ""
echo "========================================="
echo "  Connectivity Check"
echo "========================================="

# Ollama
echo -n "  Ollama (11434):  "
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    MODEL_COUNT=$(curl -s http://localhost:11434/api/tags | python3.11 -c "import json,sys; print(len(json.load(sys.stdin).get('models',[])))" 2>/dev/null || echo "?")
    echo "OK ($MODEL_COUNT models)"
else
    echo "FAILED"
fi

# MCPO
echo -n "  MCPO (8300):     "
if curl -s http://localhost:8300/ > /dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
fi

# Open WebUI
echo -n "  Open WebUI (8080): "
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/ 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    echo "OK (HTTP $HTTP_CODE)"
else
    echo "FAILED (HTTP $HTTP_CODE)"
fi

echo ""
