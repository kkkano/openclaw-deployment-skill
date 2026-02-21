# Docker Compose & OpenClaw Config Reference

## docker-compose.yml Template

```yaml
version: '3.8'

services:
  openclaw-gateway:
    image: openclaw-gateway:latest
    build:
      context: .
      dockerfile: Dockerfile
    container_name: openclaw-openclaw-gateway-1
    restart: unless-stopped
    ports:
      - "18789:18789"    # Gateway (main)
      # 18791: Control (auto-derived, internal)
      # 18793: Canvas (auto-derived, internal)
      # 18800: Chrome CDP (internal only, not exposed to host)
    volumes:
      - /home/ubuntu/.openclaw:/home/node/.openclaw
    shm_size: 512m       # CRITICAL: Chrome needs >64MB shared memory
    environment:
      - NODE_ENV=production
    # DO NOT use network_mode: host (breaks container DNS resolution)
```

### Key Settings

| Setting | Value | Why |
|---------|-------|-----|
| `shm_size` | `512m` | Chrome crashes with default 64MB |
| `volumes` | host `.openclaw` → container `.openclaw` | Persist config, memory, models across rebuilds |
| `ports` | `18789:18789` | Only expose gateway port; CDP stays internal |
| `restart` | `unless-stopped` | Auto-recover from crashes |

### Container Rebuild Behavior

`docker compose up -d` RECREATES the container:
- ✅ Preserved: everything in `/home/node/.openclaw` (volume mount)
- ❌ Lost: `/usr/bin/chromium` wrapper script
- ❌ Lost: running Chrome process
- ❌ Lost: any manual changes inside container

→ Always run `post-start.sh` after rebuild

## openclaw.json Complete Template

```json
{
  "gateway": {
    "port": 18789
  },
  "telegram": {
    "token": "BOT_TOKEN_HERE",
    "apiBaseUrl": "https://your-cloudflare-proxy.pages.dev",
    "commands": {
      "native": false
    },
    "multimedia": {
      "enabled": true,
      "image": true,
      "audio": true,
      "video": true
    }
  },
  "models": [
    {
      "id": "your-model-id",
      "provider": "custom",
      "apiBaseUrl": "https://your-api-proxy.com/v1",
      "apiKey": "your-api-key",
      "isDefault": true
    }
  ],
  "skills": {
    "maxSkillsPromptChars": 120000
  },
  "memory": {
    "backend": "builtin"
  },
  "browser": {
    "executablePath": "/usr/bin/chromium",
    "headless": true,
    "noSandbox": true,
    "defaultProfile": "openclaw",
    "profiles": {
      "openclaw": {
        "cdpPort": 18800,
        "color": "#FF4500"
      },
      "chrome": {
        "cdpPort": 18800,
        "color": "#FF4500"
      }
    }
  }
}
```

### Config Hot Reload

OpenClaw watches `openclaw.json` for changes and auto-applies them:

```
config hot reload applied (browser.profiles)
config hot reload applied (telegram.multimedia)
config hot reload applied (skills.maxSkillsPromptChars)
```

No need to restart the container. Changes take effect in ~5 seconds.

### What DOES Require Restart

- `docker-compose.yml` changes (ports, volumes, shm_size)
- Dockerfile changes
- Model file changes (need re-import)

## Directory Map

```
/home/ubuntu/                              # Host
├── openclaw/                              # OpenClaw source + Docker files
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── post-start.sh                      # Browser setup after container rebuild
│   └── restart.sh                         # docker compose up -d && post-start.sh
│
├── .openclaw/                             # OpenClaw data (volume-mounted)
│   ├── openclaw.json                      # Master config (hot-reload)
│   ├── workspace/
│   │   ├── SOUL.md                        # Bot personality
│   │   ├── USER.md                        # User profile
│   │   ├── skills/                        # 161 skill definitions
│   │   └── memories/                      # Memory markdown files
│   ├── memory/
│   │   └── default.sqlite                 # Vector memory database
│   ├── models/
│   │   └── embeddinggemma-300m-qat-Q8_0.gguf  # Local embedding (314MB)
│   └── agents/default/sessions/
│       ├── *.jsonl                         # Full conversation logs
│       └── sessions.json                   # Session metadata
│
├── openclaw-memory/                       # Memory sync repo (GitHub)
│   ├── telegram-bot/{db,export,sessions}
│   └── shared/config-sanitized.json
│
├── scripts/
│   └── sync-memory.sh                     # Cron memory sync script
│
└── logs/
    └── memory-sync.log                    # Sync script logs

/etc/
├── xray/config.json                       # Xray VMess proxy config
└── systemd/system/xray.service            # Xray systemd unit
```

## Common Operations

```bash
# Restart everything
cd /home/ubuntu/openclaw && sudo docker compose up -d && bash post-start.sh

# View container logs (last 100 lines)
docker logs openclaw-openclaw-gateway-1 --tail 100

# Enter container shell
docker exec -it openclaw-openclaw-gateway-1 bash

# Edit config (auto-reloads)
vim /home/ubuntu/.openclaw/openclaw.json

# Check Xray proxy
sudo systemctl status xray
curl --proxy socks5://127.0.0.1:10808 https://httpbin.org/ip

# Manual memory sync
bash /home/ubuntu/scripts/sync-memory.sh

# Check Docker network gateway IP
docker network inspect openclaw_default | grep Gateway
```
