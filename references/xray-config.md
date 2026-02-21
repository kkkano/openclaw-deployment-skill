# Xray Proxy Configuration Reference

## Installation

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

## Config Template: `/etc/xray/config.json`

```json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks",
      "port": 10808,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    },
    {
      "tag": "http",
      "port": 10809,
      "listen": "0.0.0.0",
      "protocol": "http",
      "settings": {
        "allowTransparent": false
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "YOUR_SERVER_ADDRESS",
            "port": YOUR_PORT,
            "users": [
              {
                "id": "YOUR_UUID",
                "alterId": 0,
                "security": "auto"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/YOUR_PATH"
        },
        "security": "tls",
        "tlsSettings": {
          "serverName": "YOUR_SNI"
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "outboundTag": "direct",
        "domain": ["geosite:cn"]
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "ip": ["geoip:cn", "geoip:private"]
      },
      {
        "type": "field",
        "outboundTag": "proxy",
        "port": "0-65535"
      }
    ]
  }
}
```

## Decoding VMess from Clash Subscription

```bash
# Step 1: Download and decode Clash subscription
curl -s "YOUR_SUBSCRIPTION_URL" | base64 -d > /tmp/clash-nodes.txt

# Step 2: Extract vmess:// lines
grep "^vmess://" /tmp/clash-nodes.txt > /tmp/vmess-lines.txt

# Step 3: Decode each VMess node (base64 JSON)
cat /tmp/vmess-lines.txt | head -1 | sed 's/vmess:\/\///' | base64 -d | python3 -m json.tool
```

VMess JSON fields mapping to Xray config:
- `add` → `address`
- `port` → `port`
- `id` → `users[0].id`
- `aid` → `users[0].alterId`
- `net` → `streamSettings.network`
- `path` → `wsSettings.path`
- `tls` → `streamSettings.security`
- `sni` / `host` → `tlsSettings.serverName`

## Systemd Service

```bash
# Enable and start
sudo systemctl enable xray
sudo systemctl start xray

# Check status
sudo systemctl status xray

# View logs
sudo journalctl -u xray -f

# Restart after config change
sudo systemctl restart xray
```

## Verification

```bash
# Test SOCKS5 proxy
curl --proxy socks5://127.0.0.1:10808 https://httpbin.org/ip

# Test HTTP proxy
curl --proxy http://127.0.0.1:10809 https://httpbin.org/ip

# Test from Docker container (use gateway IP)
docker exec CONTAINER curl --proxy socks5://172.19.0.1:10808 https://httpbin.org/ip

# Speed test
curl --proxy socks5://127.0.0.1:10808 -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" https://news.ycombinator.com
```

## Routing Notes

- `geosite:cn` and `geoip:cn` → direct (no proxy for domestic traffic)
- `geoip:private` → direct (local/container traffic)
- Everything else → proxy (international traffic)
- Listen on `0.0.0.0` so Docker containers can connect via host gateway IP
