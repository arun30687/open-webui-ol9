#!/bin/bash
# ============================================================
# Start all services: Ollama + MCPO + Open WebUI
# Uses systemd on OL9
# ============================================================

echo "========================================="
echo "  Starting Open WebUI Stack (OL9)"
echo "========================================="

echo ""
echo "[1/3] Ollama..."
sudo systemctl start ollama
sleep 2
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    MODEL_COUNT=$(curl -s http://localhost:11434/api/tags | python3.11 -c "import json,sys; print(len(json.load(sys.stdin).get('models',[])))" 2>/dev/null || echo "?")
    echo "  Running ($MODEL_COUNT models)"
else
    echo "  WARNING: Ollama not responding yet. Check: sudo journalctl -u ollama -f"
fi

echo ""
echo "[2/3] MCPO..."
sudo systemctl start mcpo
sleep 5
if curl -s http://localhost:8300/ > /dev/null 2>&1; then
    echo "  Running"
else
    echo "  Waiting for MCP server init (may take 15-30s for npx)..."
    for i in $(seq 1 15); do
        if curl -s http://localhost:8300/ > /dev/null 2>&1; then
            echo "  Running"
            break
        fi
        sleep 2
    done
fi

echo ""
echo "[3/3] Open WebUI..."
sudo systemctl start open-webui
echo "  Waiting for startup..."
for i in $(seq 1 30); do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "  Running"
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        echo "  WARNING: Slow startup. Check: sudo journalctl -u open-webui -f"
    fi
done

echo ""
echo "========================================="
echo "  All services started!"
echo "========================================="
echo ""
echo "  Ollama:     http://localhost:11434"
echo "  MCPO:       http://localhost:8300"
echo "  Open WebUI: http://localhost:8080"
echo ""
echo "  Logs:  sudo journalctl -u ollama -f"
echo "         sudo journalctl -u mcpo -f"
echo "         sudo journalctl -u open-webui -f"
echo "========================================="
