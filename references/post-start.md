# post-start.sh Reference

Container startup recovery script. Run after every `docker compose up -d`.

## Purpose

1. Deploy Chromium wrapper script (injects `--proxy-server` flag)
2. Clean stale Chrome locks (SingletonLock/Cookie/Socket)
3. Pre-start Chrome on CDP port 18800
4. Verify CDP endpoint is responding

## Full Script

```bash
#!/bin/bash
set -e
CONTAINER="openclaw-openclaw-gateway-1"
REAL_CHROME="/root/.cache/ms-playwright/chromium-1208/chrome-linux64/chrome"
PROXY="socks5://172.19.0.1:10808"
CDP_PORT=18800
USER_DATA="/tmp/openclaw/profiles/openclaw"

echo "=== Step 1: Deploy Chromium wrapper ==="
docker exec "$CONTAINER" bash -c "cat > /usr/bin/chromium << 'WRAPPER'
#!/bin/bash
exec $REAL_CHROME --proxy-server=$PROXY \"\\\$@\"
WRAPPER
chmod +x /usr/bin/chromium"

echo "=== Step 2: Clean stale locks ==="
docker exec "$CONTAINER" bash -c "
  mkdir -p $USER_DATA
  rm -f $USER_DATA/SingletonLock $USER_DATA/SingletonCookie $USER_DATA/SingletonSocket
"

echo "=== Step 3: Pre-start Chrome ==="
docker exec -d "$CONTAINER" bash -c "
  $REAL_CHROME \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --remote-debugging-port=$CDP_PORT \
    --user-data-dir=$USER_DATA \
    --proxy-server=$PROXY \
    2>/dev/null &
"

echo "=== Step 4: Verify CDP ==="
sleep 3
docker exec "$CONTAINER" curl -s http://127.0.0.1:$CDP_PORT/json/version | head -1
echo ""
echo "Done. Chrome running on CDP port $CDP_PORT with proxy $PROXY"
```

## Key Notes

- **REAL_CHROME path**: Check actual path with `docker exec CONTAINER find / -name chrome -type f 2>/dev/null`. Playwright version number changes between updates.
- **NEVER move the Chrome binary**: It depends on `icudtl.dat` in the same directory. Moving causes ICU errors.
- **SingletonLock**: Chrome creates this on startup. If Chrome crashes, the lock remains and prevents restart. Always clean before launch.
- **`--disable-dev-shm-usage`**: Forces Chrome to use `/tmp` instead of `/dev/shm` for shared memory, as backup to the `shm_size: 512m` Docker config.
