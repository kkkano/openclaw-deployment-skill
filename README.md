# 🐱 OpenClaw Deployment Skill for Claude Code

> 在中国大陆服务器上部署 [OpenClaw](https://github.com/openclaw/openclaw) Telegram AI Bot 的完整经验指南，专为 Claude Code 设计。

## 这是什么？

这是一个 **Claude Code Skill**——把它放进 Claude Code 的 skills 目录，AI 就能直接参考这份部署经验来帮你搞定 OpenClaw 的部署。

在国内服务器上部署一个有人格、有记忆、有浏览器、有 161 个技能的 Telegram AI Bot，你会遇到的每一个坑，这里都记录了。

## 为什么需要这个？

在中国大陆部署 OpenClaw 面临一系列独特挑战：

| 问题 | 原因 | 没有这份 Skill 你会… |
|------|------|-------------------|
| Telegram API 连不上 | GFW 封锁 | 卡在第一步，Bot 无法上线 |
| LLM API 超时 | 无法直连 OpenAI/Anthropic | 以为是代码问题，反复调试 |
| Chrome 崩溃 / 找不到 | Docker 无桌面 + 共享内存不足 | 花几小时排查 OOM 和路径问题 |
| 浏览器能启动但访问超时 | GFW 在 TCP 层拦截国际网站 | 以为是 Chrome 配置问题 |
| WARP 装了但不工作 | WARP 端点在大陆不可用 | 浪费半天在死胡同里 |
| 记忆搜索不工作 | embedding API 代理不支持 | 以为是模型问题 |
| Chrome Profile 怎么配都报错 | AI 被工具描述引导选错 profile | 读几千行源码才能发现 |
| HuggingFace 下载模型失败 | GFW 封锁 | 找不到国内镜像源 |

**总共 21 个坑**，每个都有完整的根因分析和解决方案。

## 安装方法

### 方法一：直接复制到 Claude Code Skills 目录

```bash
git clone https://github.com/kkkano/openclaw-deployment-skill.git
cp -r openclaw-deployment-skill ~/.claude/skills/openclaw-deployment
```

### 方法二：手动下载

下载整个仓库，把内容放到 `~/.claude/skills/openclaw-deployment/` 目录下即可。

安装后 Claude Code 会自动识别这个 Skill，在你部署 OpenClaw 或排查问题时自动参考。

## 文件结构

```
openclaw-deployment/
├── SKILL.md                          # 主文档：完整部署流程 + 21 个坑 + 排查流程图
├── references/
│   ├── browser-cdp.md                # Chrome CDP 端口推导、Profile 陷阱、排查命令
│   ├── docker-config.md              # Docker Compose 配置 + openclaw.json 完整模板
│   ├── memory-sync.md                # 记忆同步脚本详解（SQLite → Markdown → GitHub）
│   ├── post-start.md                 # 容器启动修复脚本（Chromium 代理包装 + 预启动）
│   └── xray-config.md               # Xray 代理配置（VMess 解码 + systemd + 验证）
└── scripts/
    └── sync-memory.sh                # 实际使用的记忆同步脚本
```

## 覆盖内容

### 9 个阶段的完整部署流程

1. **服务器 & Docker** — 腾讯云轻量 + Docker Compose（shm_size 等关键配置）
2. **Telegram API 反代** — Cloudflare Pages Worker 绕过 GFW
3. **LLM API 配置** — API 代理服务接入
4. **Skills 同步** — Python 递归脚本同步 161 个 Skills + 提示词大小限制
5. **人格注入** — SOUL.md / USER.md 配置
6. **记忆系统** — 本地 embedding 模型（hf-mirror.com 镜像下载 GGUF）
7. **多模态** — 图片/音频/视频识别
8. **浏览器自动化**（最复杂） — Chrome 安装、OOM 修复、CDP 端口推导、GFW 代理（WARP 失败 → Xray + Chromium 包装脚本）、Profile 自动选择陷阱
9. **记忆同步** — Telegram Bot ↔ GitHub ↔ Claude Code 双向同步架构

### 21 个踩坑记录

每个都包含：
- **问题现象**：你会看到什么错误
- **根因分析**：为什么会这样
- **解决方案**：具体怎么修

### 排查流程图

```
Bot 不响应？
├─ 容器运行中？ → docker ps
├─ Telegram 代理通？ → curl 反代地址
└─ LLM API 通？ → curl API 地址

记忆不工作？
├─ 模型文件在？ → ls models/*.gguf
├─ SQLite 表在？ → sqlite3 .tables
└─ embedding 正常？ → 查容器日志

浏览器不工作？
├─ Chrome 进程在？ → pgrep chrome
├─ CDP 端口响应？ → curl :18800/json/version
├─ 代理通？ → curl --proxy socks5://... httpbin.org
├─ Profile 正确？ → 两个都指向 CDP 18800
└─ 页面能加载？ → 检查 GFW + Xray
```

## 适用场景

- ✅ 在中国大陆云服务器（腾讯云/阿里云/华为云）上部署 OpenClaw
- ✅ 需要 Telegram Bot + 浏览器 + 记忆 + Skills 的完整功能
- ✅ 需要绕过 GFW 访问国际网站和 API
- ✅ 需要 Claude Code 和 Telegram Bot 共享记忆
- ✅ 排查已有部署的各种问题

## 技术栈

- **OpenClaw**: [openclaw/openclaw](https://github.com/openclaw/openclaw)
- **服务器**: Ubuntu 22.04 on Tencent Cloud
- **容器**: Docker + Docker Compose
- **代理**: Xray (VMess) + Chromium wrapper script
- **Telegram 反代**: Cloudflare Pages
- **Embedding**: embeddinggemma-300m (GGUF, via node-llama-cpp)
- **记忆同步**: cron + SQLite → Markdown + GitHub

## License

MIT

---

_部署过程踩了 21 个坑，写了 7 个诊断脚本，读了几千行 OpenClaw 源码。希望这份 Skill 能让你少走弯路。_
