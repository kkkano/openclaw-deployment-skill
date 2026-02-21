# Browser CDP Architecture & Troubleshooting Reference

## Port Derivation Chain

OpenClaw derives all ports from the gateway base port (default: 18789).

```
Gateway Port: 18789 (configurable)
    │
    ├─ Control Port:      18789 + 2  = 18791  (OpenClaw internal control API)
    ├─ Canvas Port:       18789 + 4  = 18793  (Canvas/drawing service, NOT Chrome!)
    └─ CDP Range Start:   18789 + 11 = 18800  (Chrome DevTools Protocol)
```

Source code: `/app/src/config/port-defaults.ts`

```typescript
// Simplified derivation logic
function derivePort(base: number, offset: number, fallback: number): number {
  return base ? base + offset : fallback;
}

CONTROL_PORT    = derivePort(gatewayPort, 2, 18791)
CANVAS_PORT     = derivePort(gatewayPort, 4, 18793)
CDP_PORT_START  = derivePort(gatewayPort, 11, 18800)
```

## Profile System Architecture

### Auto-Created Profiles

OpenClaw creates two default profiles:

| Profile | Driver | Created By | Purpose |
|---------|--------|-----------|---------|
| `openclaw` | CDP | `resolveBrowserConfig()` | Default headless profile |
| `chrome` | **extension** | `ensureDefaultChromeExtensionProfile()` | Chrome Extension relay |

### The Extension Relay Trap

**Problem**: In Docker (no desktop), extension relay NEVER works. But the AI model's tool description says:

```
"For Chrome Extension relay, use profile='chrome'"
```

The AI model reads this → passes `profile="chrome"` → OpenClaw tries extension relay → fails with:
```
"Chrome extension relay is running, but no tab is connected"
```

**Solution**: Override both profiles to use CDP:

```json
{
  "browser": {
    "profiles": {
      "openclaw": { "cdpPort": 18800 },
      "chrome": { "cdpPort": 18800 }
    }
  }
}
```

### Source Files (for debugging)

| File | Purpose |
|------|---------|
| `/app/src/browser/config.ts` | `resolveBrowserConfig()`, port derivation |
| `/app/src/browser/constants.ts` | Default port values |
| `/app/src/browser/chrome.ts` | `launchOpenClawChrome()`, `ensurePortAvailable()` |
| `/app/src/browser/server-context.ts` | `ensureBrowserAvailable()`: HTTP → WebSocket → launch |
| `/app/src/browser/profiles.ts` | `ensureDefaultChromeExtensionProfile()` auto-creates "chrome" |
| `/app/src/agents/tools/browser-tool.ts` | Tool description that guides AI profile selection |

## Browser Startup Sequence

```
ensureBrowserAvailable()
    │
    ├─ Step 1: HTTP check → curl http://127.0.0.1:18800/json/version
    │   └─ Success? → Step 2
    │   └─ Fail? → Launch Chrome
    │
    ├─ Step 2: WebSocket check → connect to wsUrl from /json/version
    │   └─ Success? → Return (browser ready)
    │   └─ Fail? → Launch Chrome
    │
    └─ Step 3: Launch Chrome
        ├─ Clean SingletonLock
        ├─ Find executable (executablePath or auto-detect)
        ├─ Launch with --remote-debugging-port=18800
        └─ Wait for CDP to respond
```

## Chromium Wrapper Script

```bash
#!/bin/bash
# /usr/bin/chromium (inside container)
# This REPLACES the original chromium binary path
# The REAL Chrome binary stays in Playwright directory (ICU dependency!)
REAL_CHROME="/root/.cache/ms-playwright/chromium-1208/chrome-linux64/chrome"
exec "$REAL_CHROME" --proxy-server=socks5://172.19.0.1:10808 "$@"
```

### Why a Wrapper?

1. Chrome ignores `HTTP_PROXY`/`SOCKS_PROXY` environment variables
2. `--proxy-server` must be passed as CLI argument
3. OpenClaw calls `executablePath` → wrapper intercepts → injects proxy → calls real Chrome
4. Real binary MUST stay in Playwright dir (alongside `icudtl.dat`)

## Troubleshooting Commands

```bash
CONTAINER="openclaw-openclaw-gateway-1"

# === Process checks ===
# Is Chrome running?
docker exec $CONTAINER pgrep -a -f "chrome.*remote-debugging"

# What's listening on port 18800?
docker exec $CONTAINER ss -tlnp | grep 18800

# === CDP checks ===
# HTTP endpoint
docker exec $CONTAINER curl -s http://127.0.0.1:18800/json/version

# List open tabs
docker exec $CONTAINER curl -s http://127.0.0.1:18800/json/list

# === Proxy checks ===
# From container to host proxy
docker exec $CONTAINER curl -s --proxy socks5://172.19.0.1:10808 https://httpbin.org/ip

# Full chain test: Chrome → proxy → internet
docker exec $CONTAINER curl -s --proxy socks5://172.19.0.1:10808 -o /dev/null -w "%{http_code} %{time_total}s\n" https://news.ycombinator.com

# === Profile checks ===
# Check user data directory
docker exec $CONTAINER ls -la /tmp/openclaw/profiles/openclaw/

# Check for stale locks
docker exec $CONTAINER ls -la /tmp/openclaw/profiles/openclaw/SingletonLock 2>&1

# === Log checks ===
# OpenClaw container logs
docker logs $CONTAINER --tail 100 2>&1 | grep -i "browser\|chrome\|cdp\|profile"

# Chrome stderr (if launched in foreground)
docker exec $CONTAINER cat /tmp/openclaw/chrome-stderr.log 2>/dev/null

# === Recovery ===
# Kill all Chrome processes
docker exec $CONTAINER pkill -f chrome

# Clean locks and restart
docker exec $CONTAINER rm -f /tmp/openclaw/profiles/openclaw/Singleton*
# Then run post-start.sh
```

## Common Error Messages

| Error | Cause | Fix |
|-------|-------|-----|
| `Chrome extension relay is running, but no tab is connected` | AI selected extension profile | Define both profiles as CDP |
| `net::ERR_TIMED_OUT` on navigation | GFW blocking + no proxy | Chromium wrapper + Xray |
| `SingletonLock: File exists` | Crashed Chrome left lock | `rm SingletonLock` |
| `ICU data not found` | Chrome binary moved | Keep in Playwright dir, use wrapper |
| `/dev/shm: No space left` | Default 64MB too small | `shm_size: 512m` in docker-compose |
| `Snapshot timeout` | Chrome not running or CDP port wrong | Verify 18800 (not 18793) |
| `executable not found` | No executablePath in config | Set `browser.executablePath` |
