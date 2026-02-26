#!/bin/bash
# ============================================================
# Stop all services
# ============================================================

echo "========================================="
echo "  Stopping Open WebUI Stack"
echo "========================================="

echo "Stopping Open WebUI..."
sudo systemctl stop open-webui

echo "Stopping MCPO..."
sudo systemctl stop mcpo

echo "Stopping Ollama..."
sudo systemctl stop ollama

echo ""
echo "All services stopped."
echo ""
echo "  Status: sudo systemctl status ollama mcpo open-webui"
