#!/bin/bash
# ============================================================
# OpenClaw Memory Sync Script
# 把 Telegram Bot 的记忆同步到 GitHub，供 Claude Code 读取
# ============================================================

set -euo pipefail

OPENCLAW_DIR="/home/ubuntu/.openclaw"
REPO_DIR="/home/ubuntu/openclaw-memory"
BOT_DIR="$REPO_DIR/telegram-bot"
SHARED_DIR="$REPO_DIR/shared"
LOG_FILE="/home/ubuntu/logs/memory-sync.log"

log() { echo "[$(date +%Y-%m-%dT%H:%M:%S)] $*" >> "$LOG_FILE"; }

log "=== Memory sync started ==="

# 确保目录存在
mkdir -p "$BOT_DIR"/{db,sessions,export} "$SHARED_DIR"

# ---- 1. 复制 SQLite 记忆数据库（Docker 容器以 root 写入，需要 sudo） ----
if [ -f "$OPENCLAW_DIR/memory/default.sqlite" ]; then
  sudo cp "$OPENCLAW_DIR/memory/default.sqlite" "$BOT_DIR/db/memory.sqlite"
  sudo chown ubuntu:ubuntu "$BOT_DIR/db/memory.sqlite"
  log "Copied memory.sqlite"
fi

# ---- 2. 导出记忆为 Markdown（Claude Code 可读） ----
CHUNK_COUNT="0"
if command -v sqlite3 &>/dev/null && [ -f "$BOT_DIR/db/memory.sqlite" ]; then
  CHUNK_COUNT=$(sqlite3 "$BOT_DIR/db/memory.sqlite" "SELECT COUNT(*) FROM chunks;" 2>/dev/null || echo "0")
  FILE_COUNT=$(sqlite3 "$BOT_DIR/db/memory.sqlite" "SELECT COUNT(*) FROM files;" 2>/dev/null || echo "0")

  EXPORT_FILE="$BOT_DIR/export/memory-export.md"

  echo "# Telegram Bot Memory Export" > "$EXPORT_FILE"
  echo "" >> "$EXPORT_FILE"
  echo "> Auto-generated at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$EXPORT_FILE"
  echo "> Source: OpenClaw Telegram Bot (@ufomiaobot)" >> "$EXPORT_FILE"
  echo "" >> "$EXPORT_FILE"

  echo "## Memory Chunks ($CHUNK_COUNT entries)" >> "$EXPORT_FILE"
  echo "" >> "$EXPORT_FILE"

  if [ "$CHUNK_COUNT" -gt 0 ]; then
    sqlite3 "$BOT_DIR/db/memory.sqlite" \
      "SELECT '### Source: ' || path || char(10) || char(10) || text || char(10) || char(10) || '---' || char(10) FROM chunks ORDER BY updated_at DESC;" \
      >> "$EXPORT_FILE" 2>/dev/null
  else
    echo "_No memory chunks stored yet._" >> "$EXPORT_FILE"
  fi

  echo "" >> "$EXPORT_FILE"
  echo "## Indexed Files ($FILE_COUNT)" >> "$EXPORT_FILE"
  echo "" >> "$EXPORT_FILE"

  if [ "$FILE_COUNT" -gt 0 ]; then
    sqlite3 "$BOT_DIR/db/memory.sqlite" \
      "SELECT '- \`' || path || '\` (source: ' || source || ', size: ' || size || 'B)' FROM files ORDER BY mtime DESC;" \
      >> "$EXPORT_FILE" 2>/dev/null
  else
    echo "_No files indexed yet._" >> "$EXPORT_FILE"
  fi

  log "Exported memory to Markdown ($CHUNK_COUNT chunks, $FILE_COUNT files)"
fi

# ---- 3. 复制会话元数据（Docker 容器以 root 写入，需要 sudo） ----
if [ -f "$OPENCLAW_DIR/agents/default/sessions/sessions.json" ]; then
  sudo cp "$OPENCLAW_DIR/agents/default/sessions/sessions.json" "$BOT_DIR/sessions/sessions-meta.json"
  sudo chown ubuntu:ubuntu "$BOT_DIR/sessions/sessions-meta.json"
  log "Copied sessions metadata"
fi

# ---- 4. 导出会话统计 ----
STATS_FILE="$BOT_DIR/sessions/session-stats.md"
echo "# Session Statistics" > "$STATS_FILE"
echo "" >> "$STATS_FILE"
echo "> Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATS_FILE"
echo "" >> "$STATS_FILE"

SESSION_COUNT=$(find "$OPENCLAW_DIR/agents/default/sessions/" -name "*.jsonl" 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$OPENCLAW_DIR/agents/default/sessions/" 2>/dev/null | cut -f1)
echo "- Total sessions: $SESSION_COUNT" >> "$STATS_FILE"
echo "- Total size: $TOTAL_SIZE" >> "$STATS_FILE"

log "Generated session stats"

# ---- 5. 复制核心配置（脱敏） ----
if [ -f "$OPENCLAW_DIR/openclaw.json" ] && command -v python3 &>/dev/null; then
  python3 -c "
import json, re
with open('$OPENCLAW_DIR/openclaw.json') as f:
    cfg = json.load(f)
def sanitize(obj):
    if isinstance(obj, dict):
        return {k: '***' if any(s in k.lower() for s in ['token','key','secret','password','apikey','apibaseurl']) else sanitize(v) for k,v in obj.items()}
    elif isinstance(obj, list):
        return [sanitize(i) for i in obj]
    return obj
with open('$SHARED_DIR/config-sanitized.json', 'w') as f:
    json.dump(sanitize(cfg), f, indent=2, ensure_ascii=False)
" 2>/dev/null
  log "Exported sanitized config"
fi

# ---- 6. 生成同步状态 ----
echo "{\"lastSync\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"hostname\": \"$(hostname)\", \"memoryChunks\": $CHUNK_COUNT}" > "$REPO_DIR/.sync-status.json"

# ---- 7. Git commit & push ----
cd "$REPO_DIR"
git add -A
if ! git diff --cached --quiet; then
  git commit -m "chore: sync bot memory $(date +%Y-%m-%d_%H:%M)"
  git push origin main 2>&1 | tee -a "$LOG_FILE"
  log "Pushed to GitHub"
else
  log "No changes to push"
fi

log "=== Memory sync completed ==="
