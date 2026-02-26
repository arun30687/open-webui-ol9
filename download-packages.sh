#!/bin/bash
# ============================================================
# Run this on a machine WITH internet to download all packages
# for offline transfer to the OL9 VM
# ============================================================
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo "  Download Packages for Offline Transfer"
echo "========================================="

mkdir -p "$BASE_DIR/packages"

# ── 1. Pip packages ───────────────────────────────────────
echo ""
echo "[1/3] Downloading Python packages..."
pip download open-webui mcpo -d "$BASE_DIR/packages/" 2>&1 | tail -5
echo "  Downloaded to packages/"

# ── 2. Ollama ─────────────────────────────────────────────
echo ""
echo "[2/3] Downloading Ollama binary..."
if [ ! -f "$BASE_DIR/ollama-linux-amd64.tgz" ]; then
    curl -L https://ollama.com/download/ollama-linux-amd64.tgz -o "$BASE_DIR/ollama-linux-amd64.tgz"
    echo "  Downloaded ollama-linux-amd64.tgz"
else
    echo "  Already exists."
fi

# ── 3. Ollama models ─────────────────────────────────────
echo ""
echo "[3/3] Exporting Ollama model files..."
OLLAMA_DIR="$HOME/.ollama"
if [ -d "$OLLAMA_DIR/models" ]; then
    tar -czf "$BASE_DIR/ollama-models.tar.gz" -C "$OLLAMA_DIR" models
    echo "  Exported to ollama-models.tar.gz"
else
    echo "  WARNING: No Ollama models found at $OLLAMA_DIR"
    echo "  Pull a model first: ollama pull qwen2.5:7b"
fi

# ── 4. Node.js ────────────────────────────────────────────
echo ""
echo "[Bonus] Downloading Node.js..."
if [ ! -f "$BASE_DIR"/node-*-linux-x64.tar.xz ]; then
    curl -L https://nodejs.org/dist/v20.11.1/node-v20.11.1-linux-x64.tar.xz \
        -o "$BASE_DIR/node-v20.11.1-linux-x64.tar.xz"
    echo "  Downloaded Node.js"
else
    echo "  Already exists."
fi

echo ""
echo "========================================="
echo "  All packages downloaded!"
echo "========================================="
echo ""
echo "  Transfer these to the VM:"
echo ""
du -sh "$BASE_DIR/packages" "$BASE_DIR/ollama-linux-amd64.tgz" "$BASE_DIR/ollama-models.tar.gz" "$BASE_DIR"/node-*-linux-x64.tar.xz 2>/dev/null
echo ""
echo "  Total:"
du -sh "$BASE_DIR/packages" "$BASE_DIR"/*.tgz "$BASE_DIR"/*.tar.* 2>/dev/null | tail -1
