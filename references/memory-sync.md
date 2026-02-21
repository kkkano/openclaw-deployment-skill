# Memory Sync Script Reference

## Script: `/home/ubuntu/scripts/sync-memory.sh`

Cron-driven script that exports OpenClaw memory to a GitHub private repo for Claude Code consumption.

## Data Flow

```
OpenClaw Container (root-owned files)
    │
    ├─ memory/default.sqlite ──► sudo cp ──► telegram-bot/db/memory.sqlite
    │                                              │
    │                                    sqlite3 export ──► telegram-bot/export/memory-export.md
    │
    ├─ sessions/sessions.json ──► sudo cp ──► telegram-bot/sessions/sessions-meta.json
    │
    └─ openclaw.json ──► python3 sanitize ──► shared/config-sanitized.json

                                    ↓
                            git add + commit + push
                                    ↓
                          GitHub Private Repo (openclaw-memory)
```

## Key Implementation Details

### Root Permission Handling

Docker container runs as root, continuously overwrites files with `0600/root:root`:

```bash
# WRONG: Permission denied
cp "$OPENCLAW_DIR/memory/default.sqlite" "$BOT_DIR/db/memory.sqlite"

# CORRECT: sudo + chown
sudo cp "$OPENCLAW_DIR/memory/default.sqlite" "$BOT_DIR/db/memory.sqlite"
sudo chown ubuntu:ubuntu "$BOT_DIR/db/memory.sqlite"
```

### SQLite to Markdown Export

Claude Code can't natively read SQLite. Export key tables to Markdown:

```bash
sqlite3 "$BOT_DIR/db/memory.sqlite" \
  "SELECT '### Source: ' || path || char(10) || char(10) || text || char(10) || '---' || char(10) FROM chunks ORDER BY updated_at DESC;" \
  >> "$EXPORT_FILE"
```

This extracts:
- `chunks` table: memory fragments with source path and text content
- `files` table: indexed file list with source and size
- Ordered by `updated_at DESC` (newest first)

### Config Sanitization

Python script strips sensitive fields before pushing to GitHub:

```python
def sanitize(obj):
    if isinstance(obj, dict):
        return {
            k: '***' if any(s in k.lower() for s in [
                'token', 'key', 'secret', 'password', 'apikey', 'apibaseurl'
            ]) else sanitize(v)
            for k, v in obj.items()
        }
    elif isinstance(obj, list):
        return [sanitize(i) for i in obj]
    return obj
```

### Git Commit Guard

Only commits if there are actual changes:

```bash
git add -A
if ! git diff --cached --quiet; then
  git commit -m "chore: sync bot memory $(date +%Y-%m-%d_%H:%M)"
  git push origin main
fi
```

## Cron Configuration

```bash
# Every 6 hours
0 */6 * * * /home/ubuntu/scripts/sync-memory.sh >> /home/ubuntu/logs/memory-sync.log 2>&1
```

## Monitoring

Check sync log:
```bash
tail -20 /home/ubuntu/logs/memory-sync.log
```

Check last sync status:
```bash
cat /home/ubuntu/openclaw-memory/.sync-status.json
```

Verify GitHub:
```bash
gh repo view kkkano/openclaw-memory --json pushedAt
```

## GitHub Setup Requirements

1. **SSH key**: `ssh-keygen -t ed25519 -C "openclaw-memory-sync"`
2. **Deploy key**: Added to repo with write access
3. **Git config**: user.name + user.email set globally
4. **known_hosts**: `ssh-keyscan github.com >> ~/.ssh/known_hosts`
