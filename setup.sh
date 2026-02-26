#!/bin/bash
# ============================================================
# One-time setup on Oracle Linux 9 (air-gapped / no internet)
#
# Prerequisites — transfer these files to the VM first:
#   1. ollama-linux-amd64.tgz      (Ollama binary)
#   2. ollama-models.tar.gz        (Model weights)
#   3. node-v20.x-linux-x64.tar.xz (Node.js binary)
#   4. packages/                    (pip wheels directory)
#
# To download packages on internet machine:
#   pip download open-webui mcpo -d ./packages/ \
#       --python-version 3.11 --platform manylinux2014_x86_64 \
#       --only-binary=:all:
#   # Also get source packages for any that fail:
#   pip download open-webui mcpo -d ./packages/
# ============================================================
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo "  Open WebUI + MCP Setup (OL9 VM)"
echo "========================================="

# ── 1. Check OS ───────────────────────────────────────────
echo ""
echo "[1/6] Checking OS..."
if [ -f /etc/oracle-release ]; then
    cat /etc/oracle-release
elif [ -f /etc/redhat-release ]; then
    cat /etc/redhat-release
else
    echo "  WARNING: Not Oracle Linux / RHEL"
fi

# ── 2. Install Python 3.11 ────────────────────────────────
echo ""
echo "[2/6] Python 3.11..."
if command -v python3.11 &> /dev/null; then
    echo "  Already installed: $(python3.11 --version)"
else
    echo "  Installing Python 3.11 via dnf..."
    sudo dnf install -y python3.11 python3.11-pip python3.11-devel 2>/dev/null || {
        echo "  ERROR: Could not install Python 3.11."
        echo "  For air-gapped: sudo dnf install --disablerepo='*' --enablerepo='ol9_appstream' python3.11"
        echo "  Or transfer python3.11 RPMs manually."
        exit 1
    }
fi

# ── 3. Install Node.js ────────────────────────────────────
echo ""
echo "[3/6] Node.js..."
if command -v node &> /dev/null; then
    echo "  Already installed: $(node --version)"
else
    if [ -f "$BASE_DIR/node-"*"-linux-x64.tar.xz" ]; then
        echo "  Installing from local archive..."
        sudo tar -xf "$BASE_DIR"/node-*-linux-x64.tar.xz -C /usr/local --strip-components=1
        echo "  Installed: $(node --version)"
    else
        echo "  ERROR: Node.js not found."
        echo "  Transfer node-v20.x-linux-x64.tar.xz to this directory."
        exit 1
    fi
fi

# ── 4. Install Ollama ─────────────────────────────────────
echo ""
echo "[4/6] Ollama..."
if command -v ollama &> /dev/null; then
    echo "  Already installed"
else
    if [ -f "$BASE_DIR/ollama-linux-amd64.tgz" ]; then
        echo "  Installing from local archive..."
        sudo tar -xzf "$BASE_DIR/ollama-linux-amd64.tgz" -C /usr/local
        echo "  Installed: $(ollama --version 2>/dev/null || echo 'OK')"
    else
        echo "  ERROR: ollama-linux-amd64.tgz not found."
        echo "  Download from: https://ollama.com/download/ollama-linux-amd64.tgz"
        exit 1
    fi
fi

# Restore model files
if [ -f "$BASE_DIR/ollama-models.tar.gz" ]; then
    echo "  Restoring model files..."
    OLLAMA_HOME="${OLLAMA_HOME:-/usr/share/ollama/.ollama}"
    sudo mkdir -p "$OLLAMA_HOME"
    sudo tar -xzf "$BASE_DIR/ollama-models.tar.gz" -C "$OLLAMA_HOME/"
    sudo chown -R ollama:ollama "$OLLAMA_HOME" 2>/dev/null || true
    echo "  Models restored."
fi

# Create systemd service for Ollama
echo "  Creating Ollama systemd service..."
sudo tee /etc/systemd/system/ollama.service > /dev/null << 'UNIT'
[Unit]
Description=Ollama LLM Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="HOME=/usr/share/ollama"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_NUM_PARALLEL=2"
Environment="OLLAMA_MAX_LOADED_MODELS=1"

[Install]
WantedBy=default.target
UNIT

# Create ollama user if not exists
id ollama &>/dev/null || sudo useradd -r -s /bin/false -U -d /usr/share/ollama ollama
sudo mkdir -p /usr/share/ollama/.ollama
sudo chown -R ollama:ollama /usr/share/ollama

sudo systemctl daemon-reload
sudo systemctl enable ollama
echo "  Ollama service created."

# ── 5. Create Python venv ─────────────────────────────────
echo ""
echo "[5/6] Python environment..."

if [ ! -d "$BASE_DIR/venv" ]; then
    echo "  Creating virtual environment..."
    python3.11 -m venv "$BASE_DIR/venv"
fi

source "$BASE_DIR/venv/bin/activate"
pip install --quiet --upgrade pip 2>/dev/null || true

if [ -d "$BASE_DIR/packages" ] && [ "$(ls -A $BASE_DIR/packages)" ]; then
    echo "  Installing from local packages (offline)..."
    pip install --no-index --find-links="$BASE_DIR/packages" open-webui mcpo 2>&1 | tail -3
else
    echo "  Installing from PyPI (online)..."
    pip install --quiet open-webui mcpo 2>&1 | tail -3
fi
echo "  Packages installed."

# ── 6. Create systemd services ────────────────────────────
echo ""
echo "[6/6] Creating systemd services..."

# MCPO service
sudo tee /etc/systemd/system/mcpo.service > /dev/null << UNIT
[Unit]
Description=MCPO - MCP to OpenAPI Proxy
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$BASE_DIR
ExecStart=$BASE_DIR/venv/bin/mcpo --config $BASE_DIR/mcpo/config.json --host 0.0.0.0 --port 8300
Restart=always
RestartSec=5
Environment="PATH=$BASE_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=default.target
UNIT

# Open WebUI service
sudo tee /etc/systemd/system/open-webui.service > /dev/null << UNIT
[Unit]
Description=Open WebUI
After=network-online.target ollama.service mcpo.service

[Service]
Type=simple
WorkingDirectory=$BASE_DIR
ExecStart=$BASE_DIR/venv/bin/open-webui serve
Restart=always
RestartSec=5
Environment="DATA_DIR=$BASE_DIR/data"
Environment="OLLAMA_BASE_URL=http://localhost:11434"
Environment="WEBUI_AUTH=true"
Environment="ENABLE_API_KEY=true"
Environment="PATH=$BASE_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=default.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable mcpo open-webui
echo "  Services created: ollama, mcpo, open-webui"

# ── Firewall ──────────────────────────────────────────────
echo ""
echo "  Opening firewall ports..."
sudo firewall-cmd --permanent --add-port=8080/tcp 2>/dev/null || true
sudo firewall-cmd --permanent --add-port=8300/tcp 2>/dev/null || true
sudo firewall-cmd --permanent --add-port=11434/tcp 2>/dev/null || true
sudo firewall-cmd --reload 2>/dev/null || true
echo "  Ports 8080, 8300, 11434 opened."

echo ""
echo "========================================="
echo "  Setup complete!"
echo "========================================="
echo ""
echo "  Next steps:"
echo "    1. cp mcpo/config.json.example mcpo/config.json"
echo "    2. Edit mcpo/config.json with your MCP server config"
echo "    3. ./start.sh                    (start all services)"
echo "    4. Open http://<VM_IP>:8080      (create account)"
echo "    5. ./register-pipe.sh            (register the pipe)"
echo "    6. Select 'GitHub MCP Agent' model in the UI"
echo ""
