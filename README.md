# Open WebUI + MCP (Oracle Linux 9 — Air-Gapped)

Run **Open WebUI** with **MCP tool integration** on Oracle Linux 9 — supports air-gapped / no-internet environments.

## Architecture

```
┌─────────────┐     ┌──────────┐     ┌────────────────┐
│  Open WebUI  │────▶│   MCPO   │────▶│  MCP Server    │
│  (port 8080) │     │ (port 8300)    │  (GitHub/EM/..) │
└──────┬───────┘     └──────────┘     └────────────────┘
       │
       ▼
┌─────────────┐
│   Ollama    │
│ (port 11434)│
└─────────────┘
```

All services run natively — **no Docker required**.

## Quick Start (With Internet)

```bash
# 1. Setup (installs Python, Node, Ollama, pip packages, systemd services)
sudo ./setup.sh

# 2. Configure MCP server
cp mcpo/config.json.example mcpo/config.json
# Edit mcpo/config.json

# 3. Start
./start.sh

# 4. Open http://<VM_IP>:8080 → Create account

# 5. Register pipe (one-time)
./register-pipe.sh
```

## Quick Start (Air-Gapped / No Internet)

### Step 1: On a machine WITH internet

```bash
# Download all packages
./download-packages.sh

# Or manually download:
pip download open-webui mcpo -d ./packages/
curl -L https://ollama.com/download/ollama-linux-amd64.tgz -o ollama-linux-amd64.tgz
curl -L https://nodejs.org/dist/v20.11.1/node-v20.11.1-linux-x64.tar.xz -o node-v20.11.1-linux-x64.tar.xz
ollama pull qwen2.5:7b
tar -czf ollama-models.tar.gz -C ~/.ollama models
```

### Step 2: Transfer to VM

```bash
# Transfer the entire repo directory to the VM
scp -r open-webui-ol9/ user@vm:/opt/open-webui/

# Or use USB, shared folder, etc.
```

Expected transfer size:

| File | Size |
|------|------|
| packages/ (pip wheels) | ~1-2 GB |
| ollama-linux-amd64.tgz | ~100 MB |
| ollama-models.tar.gz (7b) | ~4.5 GB |
| node-v20-linux-x64.tar.xz | ~25 MB |
| **Total** | **~6-7 GB** |

### Step 3: On the VM

```bash
cd /opt/open-webui

# Setup (installs everything from local files)
sudo ./setup.sh

# Configure
cp mcpo/config.json.example mcpo/config.json
vi mcpo/config.json

# Start
./start.sh

# Register pipe
./register-pipe.sh
```

## Service Management

```bash
./start.sh              # Start all services
./stop.sh               # Stop all services
./status.sh             # Check status of all services

# Individual service control
sudo systemctl start|stop|restart ollama
sudo systemctl start|stop|restart mcpo
sudo systemctl start|stop|restart open-webui

# View logs
sudo journalctl -u ollama -f
sudo journalctl -u mcpo -f
sudo journalctl -u open-webui -f
```

## Files

```
open-webui-ol9/
├── setup.sh                  # One-time install (creates systemd services)
├── start.sh                  # Start all (systemctl start)
├── stop.sh                   # Stop all (systemctl stop)
├── status.sh                 # Health check
├── register-pipe.sh          # Register pipe in Open WebUI (one-time)
├── download-packages.sh      # Download packages on internet machine
├── github_pipe.py            # Pipe function v0.4.0
├── mcpo/
│   └── config.json.example   # MCP server config template
├── packages/                  # [downloaded] pip wheel files
├── ollama-linux-amd64.tgz    # [downloaded] Ollama binary
├── ollama-models.tar.gz      # [downloaded] Model weights
└── node-v20-linux-x64.tar.xz # [downloaded] Node.js binary
```

## Customization for Enterprise Manager (EM)

Replace the MCP config with your EM MCP server:

```json
{
  "mcpServers": {
    "em": {
      "command": "/path/to/em-mcp-server",
      "args": ["--host", "https://em-server:7803"],
      "env": {
        "EM_USERNAME": "sysman",
        "EM_PASSWORD": "your-password"
      }
    }
  }
}
```

Then update the pipe's `MCPO_BASE_URL` valve to `http://localhost:8300/em`.

## Requirements

- Oracle Linux 9 (x86_64)
- 8GB+ RAM (16GB+ recommended for 7b model)
- Python 3.11 (from OL9 AppStream repo)
- Root/sudo access (for systemd services)

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Ollama OOM | Use smaller model: `qwen2.5:3b` (edit pipe Valves) |
| SELinux blocking | `sudo setenforce 0` or create proper SELinux policy |
| Firewall blocking | `sudo firewall-cmd --add-port=8080/tcp --permanent` |
| MCPO can't reach MCP server | Check `mcpo/config.json` command path is correct |
| Slow first start | Open WebUI downloads embedding model on first run (~500MB) |
