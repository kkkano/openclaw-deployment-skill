---
name: openclaw-deployment
description: Complete guide for deploying OpenClaw (Telegram AI Bot) on a China mainland server with Docker, GFW bypass (Xray proxy + Chromium wrapper), browser automation (CDP), memory system (local embedding model), skills sync, and GitHub-based memory synchronization between Telegram Bot and Claude Code. Covers 21 documented pitfalls with root cause analysis. Use when deploying OpenClaw, troubleshooting bot issues, or setting up AI bot infrastructure behind GFW.
---

# OpenClaw Deployment on China Mainland Server

## Overview

Deploy [OpenClaw](https://github.com/openclaw/openclaw) as a Telegram AI Bot on a China mainland cloud server (tested on Tencent Cloud Ubuntu 22.04). This skill covers the complete deployment pipeline including GFW bypass, browser automation, memory system, and cross-device memory synchronization.

### Architecture

```
User (Telegram) → Telegram API → Cloudflare Pages (reverse proxy) → China Server (OpenClaw Docker)
                                                                          │
                                                              ┌───────────┼───────────┐
                                                              │           │           │
                                                         LLM API    Browser     Memory
                                                         (proxy)   (Chrome+    (SQLite+
                                                                    Xray)      embedding)
```

### Key Constraints

- **GFW blocks**: Telegram API, OpenAI API, HuggingFace, most international sites at TCP level
- **Docker container runs as root**: file permissions require `sudo` for host-side access
- **No desktop environment**: headless Chrome only, no extension relay
- **OpenClaw hot-reloads config**: changes to `openclaw.json` take effect in seconds without restart

---

## Phase 1: Server & Docker Setup

### 1.1 Server Requirements

- **Cloud provider**: Tencent Cloud Lighthouse (or any China mainland VPS)
- **OS**: Ubuntu 22.04 LTS
- **Specs**: 2 vCPU, 4GB RAM minimum (embedding model needs ~1GB)
- **Storage**: 40GB+ (Docker images ~8GB, models ~314MB, logs grow over time)

### 1.2 Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Logout and login again
```

### 1.3 Clone & Build OpenClaw

```bash
cd /home/ubuntu
git clone https://github.com/openclaw/openclaw.git
cd openclaw
```

### 1.4 Docker Compose Configuration

Key modifications to `docker-compose.yml`:

```yaml
services:
  openclaw-gateway:
    # CRITICAL: increase shared memory for Chrome
    shm_size: 512m
    ports:
      - "18789:18789"
    volumes:
      - /home/ubuntu/.openclaw:/home/node/.openclaw
    # DO NOT set network_mode: host (breaks container DNS)
```

> **Pitfall #11**: Chrome crashes with `shm_size` at default 64MB. Set to `512m`.

### 1.5 Docker Network Gateway

Container accesses host services via Docker bridge gateway IP:

```bash
# Find gateway IP (typically 172.19.0.1 or 172.17.0.1)
docker network inspect openclaw_default | grep Gateway
```

This IP is used for:
- Xray proxy: `socks5://172.19.0.1:10808`
- Host-side services accessible from container

---

## Phase 2: Telegram API Reverse Proxy

GFW blocks `api.telegram.org`. Use Cloudflare Pages as reverse proxy.

### 2.1 Cloudflare Pages Worker

Create a Cloudflare Pages project with `functions/[[path]].js`:

```javascript
export async function onRequest(context) {
  const url = new URL(context.request.url);
  url.host = 'api.telegram.org';
  return fetch(new Request(url, context.request));
}
```

Deploy to Cloudflare Pages. The resulting URL (e.g., `https://your-project.pages.dev`) replaces `api.telegram.org`.

### 2.2 OpenClaw Telegram Config

In `openclaw.json`:

```json
{
  "telegram": {
    "token": "YOUR_BOT_TOKEN",
    "apiBaseUrl": "https://your-project.pages.dev"
  }
}
```

> **Pitfall #1**: Without reverse proxy, Bot cannot connect to Telegram at all.

---

## Phase 3: LLM API Configuration

### 3.1 API Proxy Service

China mainland cannot directly access OpenAI/Anthropic APIs. Use an API proxy service.

```json
{
  "models": [
    {
      "id": "your-model-id",
      "provider": "custom",
      "apiBaseUrl": "https://your-api-proxy.com/v1",
      "apiKey": "your-key"
    }
  ]
}
```

> **Pitfall #2**: Direct API calls timeout. Always use a proxy service.

---

## Phase 4: Skills Synchronization

### 4.1 The Problem

OpenClaw skills are stored at `/home/ubuntu/.openclaw/workspace/skills/`. Manual copying is tedious for 100+ skills with nested directories.

### 4.2 Recursive Sync Script

```python
#!/usr/bin/env python3
"""Recursively sync all SKILL.md files to OpenClaw server via SSH."""
import paramiko
import os
from pathlib import Path

LOCAL_SKILLS = os.path.expanduser("~/.claude/skills")
REMOTE_SKILLS = "/home/ubuntu/.openclaw/workspace/skills"
HOST = "your-server-ip"
USER = "ubuntu"

def sync_skills():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username=USER)
    sftp = ssh.open_sftp()

    count = 0
    for root, dirs, files in os.walk(LOCAL_SKILLS):
        for f in files:
            if f == "SKILL.md":
                local_path = os.path.join(root, f)
                # Flatten: use parent directory name as skill name
                skill_name = os.path.basename(root)
                remote_dir = f"{REMOTE_SKILLS}/{skill_name}"
                remote_path = f"{remote_dir}/SKILL.md"

                try:
                    sftp.stat(remote_dir)
                except FileNotFoundError:
                    sftp.mkdir(remote_dir)

                sftp.put(local_path, remote_path)
                count += 1
                print(f"  [{count}] {skill_name}/SKILL.md")

    sftp.close()
    ssh.close()
    print(f"\nSynced {count} skills.")

if __name__ == "__main__":
    sync_skills()
```

### 4.3 Skills Prompt Size Limit

> **Pitfall #4**: Default `maxSkillsPromptChars` is 30K, truncating to ~52 skills.

```json
{
  "skills": {
    "maxSkillsPromptChars": 120000
  }
}
```

### 4.4 Native Command Registration Limit

> **Pitfall #9**: Telegram limits to 100 native commands. Disable registration:

```json
{
  "telegram": {
    "commands": {
      "native": false
    }
  }
}
```

---

## Phase 5: Personality (SOUL.md)

### 5.1 Personality Injection

Create `/home/ubuntu/.openclaw/workspace/SOUL.md` with the bot's personality definition.

OpenClaw injects this into every conversation as system prompt. Without it, the bot responds with generic AI personality.

> **Pitfall**: Without SOUL.md, the bot has no personality and responds in a generic, utilitarian tone.

### 5.2 User Profile

Create `/home/ubuntu/.openclaw/workspace/USER.md` with user information the bot should know.

---

## Phase 6: Memory System (Local Embedding)

### 6.1 The Problem

OpenClaw's memory uses vector embeddings for semantic search. The `auto` provider tries remote embedding APIs, but most China API proxies don't support embedding endpoints.

> **Pitfall #8**: Memory search returns no results because embedding falls back to FTS (full-text search only).
> **Pitfall #13**: API proxy services typically only forward chat completion, not embedding.

### 6.2 Solution: Local Embedding Model

Download a GGUF embedding model via China-accessible mirror:

```bash
# HuggingFace is blocked by GFW. Use hf-mirror.com instead.
cd /home/ubuntu/.openclaw/models/
wget https://hf-mirror.com/nicepkg/embeddinggemma/resolve/main/embeddinggemma-300m-qat-Q8_0.gguf
```

> **Pitfall #16**: `huggingface.co` is blocked by GFW. Use `hf-mirror.com`.

### 6.3 Memory Configuration

```json
{
  "memory": {
    "backend": "builtin"
  }
}
```

OpenClaw auto-detects the local model in the `models/` directory and uses `node-llama-cpp` for inference. The model generates 768-dimensional vectors stored in SQLite with `vec0` extension.

### 6.4 Memory Database Structure

```
memory/default.sqlite
├── chunks          # Memory fragments (text + 768-dim vector embedding)
├── chunks_fts      # Full-text search index (FTS5)
├── chunks_vec      # Vector search index (vec0)
├── files           # Indexed file list
├── embedding_cache # Embedding cache
└── meta            # Model config metadata
```

---

## Phase 7: Multimodal Support

Enable image/audio/video recognition:

```json
{
  "telegram": {
    "multimedia": {
      "enabled": true,
      "image": true,
      "audio": true,
      "video": true
    }
  }
}
```

Requires the LLM model to support vision (e.g., GPT-4o, Claude with vision).

---

## Phase 8: Browser Automation (The Hard Part)

This is the most complex section. Browser setup in a headless Docker container behind GFW involves multiple interacting systems.

### 8.1 Chrome Installation

OpenClaw uses Playwright's bundled Chromium. The binary is at:

```
/root/.cache/ms-playwright/chromium-{version}/chrome-linux64/chrome
```

Configure in `openclaw.json`:

```json
{
  "browser": {
    "executablePath": "/usr/bin/chromium",
    "headless": true,
    "noSandbox": true
  }
}
```

> **Pitfall #6**: Without `executablePath`, OpenClaw tries `xdg-open` which fails in Docker.

### 8.2 Chrome OOM Fix

> **Pitfall #11**: Chrome crashes immediately. Default Docker `/dev/shm` is 64MB.

In `docker-compose.yml`:
```yaml
shm_size: 512m
```

### 8.3 Container Rebuild Persistence

> **Pitfall #12**: `docker compose up -d` recreates the container, losing symlinks and running processes.

Solution: `post-start.sh` script that runs after every container start.

See [📋 post-start.sh reference](./references/post-start.md)

### 8.4 CDP Port Derivation Chain

OpenClaw derives Chrome DevTools Protocol (CDP) ports from the gateway port:

```
Gateway Port (18789)
  → Control Port: 18789 + 2 = 18791
  → CDP Range Start: 18789 + 2 + 9 = 18800  ← Chrome listens here
  → Canvas Port: 18789 + 4 = 18793  (NOT Chrome!)
```

> **Pitfall #15**: Don't confuse port 18793 (Canvas) with 18800 (Chrome CDP).

Source: `/app/src/config/port-defaults.ts` → `derivePort(base, offset, fallback)`

### 8.5 Chrome Pre-Start Script

Chrome must be pre-started before OpenClaw tries to use it:

```bash
# Inside container (via docker exec)
CHROME_BIN="/root/.cache/ms-playwright/chromium-1208/chrome-linux64/chrome"
USER_DATA="/tmp/openclaw/profiles/openclaw"

# Clean stale locks
rm -f "$USER_DATA/SingletonLock" "$USER_DATA/SingletonCookie" "$USER_DATA/SingletonSocket"

# Launch Chrome
$CHROME_BIN \
  --headless=new \
  --no-sandbox \
  --disable-gpu \
  --remote-debugging-port=18800 \
  --user-data-dir="$USER_DATA" \
  --proxy-server=socks5://172.19.0.1:10808 \
  &

# Verify CDP is responding
sleep 3
curl -s http://127.0.0.1:18800/json/version
```

> **Pitfall #14**: Race condition if OpenClaw tries browser before Chrome is ready. Always verify CDP responds.
> **Pitfall #12**: SingletonLock from crashed Chrome prevents restart. Must clean before launch.

### 8.6 GFW Bypass for Browser (Xray Proxy)

> **Pitfall #17**: International websites (HN, Wikipedia, etc.) timeout because GFW blocks TCP.

#### 8.6.1 WARP Does NOT Work

> **Pitfall #18**: Cloudflare WARP registers and shows "Connected" but actual proxy traffic fails (exit code 97) on China mainland servers. Do not waste time on this.

#### 8.6.2 Xray + VMess Solution

Install Xray on the HOST (not in container):

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

Decode VMess node from Clash subscription:

```bash
# Clash subscription → base64 decode → extract vmess:// lines → base64 decode each
curl -s "YOUR_CLASH_SUBSCRIPTION_URL" | base64 -d | grep "^vmess://" | head -1 | sed 's/vmess:\/\///' | base64 -d
```

See [📋 Xray config reference](./references/xray-config.md)

Configure as systemd service:

```bash
sudo systemctl enable xray
sudo systemctl start xray
# Verify: SOCKS5 on 10808, HTTP on 10809
curl --proxy socks5://127.0.0.1:10808 https://news.ycombinator.com -o /dev/null -w "%{http_code} %{time_total}s"
```

#### 8.6.3 Chromium Wrapper Script (Proxy Injection)

Chrome doesn't read environment proxy variables. Inject via wrapper script:

```bash
#!/bin/bash
# /usr/bin/chromium (wrapper - replaces the binary)
REAL_CHROME="/root/.cache/ms-playwright/chromium-1208/chrome-linux64/chrome"
exec "$REAL_CHROME" --proxy-server=socks5://172.19.0.1:10808 "$@"
```

> **CRITICAL Pitfall #19**: Do NOT move the Chrome binary! It must stay in the Playwright directory alongside `icudtl.dat` (ICU data). Moving it causes `ICU data not found` errors. The wrapper script calls Chrome at its original location.

### 8.7 Chrome Profile Auto-Selection Trap

This is the subtlest pitfall in the entire deployment.

> **Pitfall #20 & #21**: OpenClaw auto-creates a "chrome" profile with `driver: "extension"` (for Chrome Extension relay). Even if you set `defaultProfile: "openclaw"`, the AI model's tool description explicitly tells it to use `profile="chrome"` for extension scenarios. In headless Docker, extension relay NEVER works.

**Root Cause Chain**:
1. `profiles.ts` → `ensureDefaultChromeExtensionProfile()` auto-creates "chrome" profile with `driver: "extension"`
2. `browser-tool.ts` → tool description tells AI: "use profile='chrome' for extension relay"
3. AI model reads tool description → passes `profile="chrome"` → tries extension relay → fails

**Solution**: Explicitly define BOTH profiles pointing to CDP:

```json
{
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

This way, regardless of which profile the AI selects, it connects via CDP to the pre-started Chrome instance.

### 8.8 Verification Checklist

```bash
# 1. Chrome process running?
docker exec CONTAINER pgrep -f "chrome.*remote-debugging-port"

# 2. CDP HTTP endpoint responding?
docker exec CONTAINER curl -s http://127.0.0.1:18800/json/version | head -1

# 3. WebSocket connectivity?
# Extract wsUrl from /json/version, test with wscat or script

# 4. Page navigation works through proxy?
docker exec CONTAINER curl -s --proxy socks5://172.19.0.1:10808 https://news.ycombinator.com | head -5

# 5. Full browser test: navigate and get title
# Send bot a message: "Visit https://news.ycombinator.com and tell me the top 3 posts"
```

---

## Phase 9: Memory Synchronization (Bot ↔ Claude Code)

### 9.1 Architecture

```
Telegram Bot (server)          GitHub Private Repo         Claude Code (local)
       │                      (openclaw-memory)                   │
       │  cron every 6h  ──►        │                            │
       │  · memory.sqlite           │       ◄── git pull         │
       │  · memory-export.md        │                            │
       │  · sessions-meta.json      │                            │
       └── telegram-bot/ ─────────► │ ◄──── claude-code/ ────────┘
                                    │
                               shared/ (bidirectional)
```

### 9.2 Setup Steps

1. **Generate SSH key on server**:
   ```bash
   ssh-keygen -t ed25519 -C "openclaw-memory-sync" -f ~/.ssh/id_ed25519 -N ""
   ```

2. **Create private GitHub repo**:
   ```bash
   gh repo create yourname/openclaw-memory --private
   ```

3. **Add deploy key** (with write access):
   ```bash
   gh repo deploy-key add ~/.ssh/id_ed25519.pub --repo yourname/openclaw-memory --title "openclaw-server" --allow-write
   ```

4. **Clone on server**:
   ```bash
   git config --global user.name "openclaw-bot"
   git config --global user.email "openclaw-bot@users.noreply.github.com"
   ssh-keyscan github.com >> ~/.ssh/known_hosts
   git clone git@github.com:yourname/openclaw-memory.git ~/openclaw-memory
   ```

5. **Deploy sync script**: See [📋 sync-memory.sh](./scripts/sync-memory.sh)

6. **Set up cron**:
   ```bash
   crontab -e
   # Add:
   0 */6 * * * /home/ubuntu/scripts/sync-memory.sh >> /home/ubuntu/logs/memory-sync.log 2>&1
   ```

7. **Clone locally**:
   ```bash
   git clone git@github.com:yourname/openclaw-memory.git D:/openclaw-memory
   ```

### 9.3 Sync Script Key Details

- Docker container writes files as **root** (`0600`), so script uses `sudo cp` + `chown`
- SQLite exported to Markdown via `sqlite3` CLI (Claude Code reads `.md`, not `.sqlite`)
- Raw `.jsonl` session logs are NOT synced (too large, contain sensitive data)
- Config exported with Python sanitizer (strips token/key/secret/password fields)
- Git commit only if there are actual changes (`git diff --cached --quiet`)

### 9.4 Repository Structure

```
openclaw-memory/
├── .sync-status.json                   # Last sync timestamp + stats
├── telegram-bot/
│   ├── db/memory.sqlite                # SQLite backup
│   ├── export/memory-export.md         # Markdown export (Claude Code reads this)
│   └── sessions/
│       ├── sessions-meta.json          # Session metadata
│       └── session-stats.md            # Session statistics
├── claude-code/                        # Reserved for Claude Code data
└── shared/
    └── config-sanitized.json           # Sanitized openclaw.json
```

---

## Configuration Reference

### Core Config: `/home/ubuntu/.openclaw/openclaw.json`

This is THE most important file. OpenClaw hot-reloads it without restart.

```json
{
  "telegram": {
    "token": "BOT_TOKEN",
    "apiBaseUrl": "https://your-cf-proxy.pages.dev",
    "commands": { "native": false },
    "multimedia": {
      "enabled": true,
      "image": true,
      "audio": true,
      "video": true
    }
  },
  "models": [
    {
      "id": "model-id",
      "provider": "custom",
      "apiBaseUrl": "https://your-api-proxy/v1",
      "apiKey": "key"
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
      "openclaw": { "cdpPort": 18800 },
      "chrome": { "cdpPort": 18800 }
    }
  }
}
```

### File Map

| File | Location | Purpose |
|------|----------|---------|
| `openclaw.json` | `/home/ubuntu/.openclaw/` | Master config (hot-reload) |
| `SOUL.md` | `/home/ubuntu/.openclaw/workspace/` | Bot personality |
| `USER.md` | `/home/ubuntu/.openclaw/workspace/` | User profile |
| `skills/` | `/home/ubuntu/.openclaw/workspace/` | Skill definitions |
| `models/` | `/home/ubuntu/.openclaw/` | Local embedding model |
| `memory/default.sqlite` | `/home/ubuntu/.openclaw/` | Memory database |
| `docker-compose.yml` | `/home/ubuntu/openclaw/` | Container config |
| `post-start.sh` | `/home/ubuntu/openclaw/` | Browser setup script |
| `sync-memory.sh` | `/home/ubuntu/scripts/` | Memory sync to GitHub |
| `config.json` | `/etc/xray/` | Xray proxy config |
| `/usr/bin/chromium` | Container | Wrapper script (proxy injection) |

---

## Pitfall Reference (21 Total)

| # | Problem | Root Cause | Solution |
|---|---------|-----------|----------|
| 1 | Bot can't connect to Telegram | GFW blocks api.telegram.org | Cloudflare Pages reverse proxy |
| 2 | LLM API timeout | GFW blocks OpenAI/Anthropic | API proxy service |
| 3 | Only 32 skills loaded | Sync script didn't handle nested dirs | Recursive scan + flatten |
| 4 | Prompt truncated to ~52 skills | `maxSkillsPromptChars` default 30K | Increase to 120K |
| 5 | Bot says "52 skills" | LLM estimation error, all 161 present | Non-issue, ignore |
| 6 | Chrome not found | No desktop, xdg-open fails | Set `executablePath` |
| 7 | Browser timeout 15s | Config not yet applied | Update config + restart |
| 8 | Memory search no results | Embedding falls back to FTS | Local embedding model |
| 9 | Command menu error | Telegram limits 100 native commands | `commands.native: false` |
| 10 | sendChatAction fails | Network fluctuation | Non-fatal, auto-recovers |
| 11 | Chrome crashes after page load | `/dev/shm` default 64MB | `shm_size: 512m` |
| 12 | Chrome won't start after rebuild | Symlinks lost + SingletonLock | `post-start.sh` |
| 13 | API proxy no embedding | Proxy only forwards chat | Local `node-llama-cpp` model |
| 14 | Snapshot/interaction timeout | Chrome not started (race) | Pre-start + verify CDP |
| 15 | CDP port confusion | 18800=Chrome, 18793=Canvas | Understand port derivation |
| 16 | HuggingFace blocked | GFW blocks huggingface.co | Use hf-mirror.com |
| 17 | International sites timeout | GFW TCP-level blocking | Xray SOCKS5 proxy |
| 18 | WARP doesn't work | WARP endpoints unreliable in China | Use Xray + VMess instead |
| 19 | Chrome ICU error | Binary moved from Playwright dir | Keep original path, use wrapper |
| 20 | defaultProfile ignored | AI model follows tool description | Define both profiles explicitly |
| 21 | Two profiles inconsistent | Auto-created chrome uses extension | Both profiles point to CDP 18800 |

---

## Troubleshooting Flowchart

```
Bot not responding?
├─ Check container running: docker ps
├─ Check logs: docker logs openclaw-openclaw-gateway-1 --tail 50
├─ Check Telegram proxy: curl https://your-cf-proxy.pages.dev/bot{TOKEN}/getMe
└─ Check LLM API: curl your-api-proxy/v1/chat/completions

Memory not working?
├─ Check model exists: ls /home/ubuntu/.openclaw/models/*.gguf
├─ Check SQLite: sqlite3 /home/ubuntu/.openclaw/memory/default.sqlite ".tables"
├─ Check embedding: look for "embedding" in container logs
└─ Verify: memory search should use vector, not just FTS

Browser not working?
├─ Chrome running?: docker exec CONTAINER pgrep -f chrome
│  └─ No → Run post-start.sh
├─ CDP responding?: curl http://127.0.0.1:18800/json/version
│  └─ No → Check SingletonLock, restart Chrome
├─ Proxy working?: curl --proxy socks5://172.19.0.1:10808 https://httpbin.org/ip
│  └─ No → Check Xray: systemctl status xray
├─ Profile correct?: Check openclaw.json browser.profiles
│  └─ Both profiles must point to cdpPort: 18800
└─ Page loads?: Try navigating to a URL via bot command
   └─ Timeout → Check GFW, verify Xray routing
```

---

## Quick Start Checklist

- [ ] Server provisioned (Ubuntu 22.04, 2C4G+)
- [ ] Docker installed and running
- [ ] OpenClaw cloned and docker-compose configured (shm_size: 512m)
- [ ] Cloudflare Pages Telegram proxy deployed
- [ ] LLM API proxy configured
- [ ] `openclaw.json` created with all settings
- [ ] `SOUL.md` and `USER.md` created
- [ ] Skills synced (recursive script)
- [ ] Embedding model downloaded via hf-mirror.com
- [ ] Xray installed and configured (SOCKS5:10808)
- [ ] `post-start.sh` deployed (Chromium wrapper + Chrome pre-start)
- [ ] Both browser profiles point to CDP 18800
- [ ] Container started: `docker compose up -d && bash post-start.sh`
- [ ] Memory sync script deployed with cron (every 6h)
- [ ] All verification checks passed
