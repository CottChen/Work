# OpenClaw 命令与配置完整指南

本文档详细介绍 OpenClaw 的所有 CLI 命令、配置参数，以及常见的错误处理方法。

## 一、CLI 命令详解

### 1. 配置与初始化命令

| 命令 | 描述 | 常用示例 |
|------|------|----------|
| `openclaw onboard` | 全功能引导式配置向导，交互式配置模型认证、网关、消息通道等 | `openclaw onboard --install-daemon` |
| `openclaw setup` | 最小化初始配置，仅生成基础配置文件 | `openclaw setup` |
| `openclaw configure` | 交互式配置编辑器，按菜单选择要修改的配置域 | `openclaw configure` |
| `openclaw config` | 直接操作配置键值，使用点号语法非交互式读取或写入 | 见下文详解 |
| `openclaw reset` | 重置配置/状态，删除配置、凭据、会话或工作区文件 | `openclaw reset --scope config+creds+sessions` |
| `openclaw uninstall` | 卸载程序，移除网关服务、状态目录和工作区 | `openclaw uninstall` |

#### openclaw config 命令详解

```bash
# 获取配置值
openclaw config get <key>
openclaw config get gateway.port
openclaw config get agents.defaults.model.primary
openclaw config get agents.list[0].id

# 设置配置值
openclaw config set <key> <value>
openclaw config set gateway.port 19001 --json
openclaw config set channels.whatsapp.groups '["*"]' --json
openclaw config set models.providers.bailian.apiKey "你的API密钥"
openclaw config set agents.defaults.model.primary "bailian/qwen3-max-2026-01-23"
openclaw config set models.providers.bailian.timeout 30

# 删除配置值
openclaw config unset <key>
openclaw config unset tools.web.search.apiKey
```

**参数说明：**
- `--json`: 将值解析为 JSON5 格式
- 支持点号语法（如 `gateway.port`）和数组索引（如 `agents.list[0].id`）

### 2. 网关与服务命令

| 命令 | 描述 | 常用示例 |
|------|------|----------|
| `openclaw gateway` | 启动网关服务（前台运行） | `openclaw gateway --port 18789 --verbose` |
| `openclaw gateway install` | 安装网关为后台服务（systemd/launchd） | `openclaw gateway install` |
| `openclaw gateway status` | 查看网关服务状态 | `openclaw gateway status` |
| `openclaw gateway stop` | 停止网关服务 | `openclaw gateway stop` |
| `openclaw gateway restart` | 重启网关服务 | `openclaw gateway restart` |
| `openclaw dashboard` | 打开 Web 控制面板 | `openclaw dashboard` |
| `openclaw tui` | 启动终端界面模式 | `openclaw tui` |

**gateway 命令参数：**
- `--port <port>`: 指定端口，默认 18789
- `--verbose`: 显示详细日志
- `--config <path>`: 指定配置文件路径

### 3. 通道与消息命令

| 命令 | 描述 | 常用示例 |
|------|------|----------|
| `openclaw channels login` | 登录消息通道 | `openclaw channels login --channel whatsapp` |
| `openclaw channels status` | 查看通道连接状态 | `openclaw channels status --probe` |
| `openclaw channels logout` | 登出并断开指定通道 | `openclaw channels logout --channel telegram` |
| `openclaw message send` | 发送消息 | `openclaw message send --target +15555550123 --message "Hello" --channel whatsapp` |
| `openclaw pairing approve` | 批准私信配对 | `openclaw pairing approve --code 123456` |

### 4. 模型管理命令

```bash
# 列出可用模型
openclaw models list
openclaw models list --all           # 显示所有模型
openclaw models list --local         # 只显示本地模型
openclaw models list --provider <name>  # 按提供商筛选
openclaw models list --plain         # 纯文本输出
openclaw models list --json          # JSON 输出

# 查看当前模型状态
openclaw models status

# 设置默认模型
openclaw models set <provider/model>
openclaw models set anthropic/claude-opus-4-5
openclaw models set claude-sonnet-4-20250514

# 设置图像生成模型
openclaw models set-image dall-e-3

# 模型别名管理
openclaw models aliases list
openclaw models aliases add <alias> <provider/model>
openclaw models aliases remove <alias>

# 备用模型配置
openclaw models fallbacks list
openclaw models fallbacks add <provider/model>
openclaw models fallbacks remove <provider/model>
openclaw models fallbacks clear

# 图像模型备用配置
openclaw models image-fallbacks list
openclaw models image-fallbacks add <provider/model>
openclaw models image-fallbacks remove <provider/model>
openclaw models image-fallbacks clear

# 扫描新模型
openclaw models scan
```

### 5. 技能（Skills）命令

```bash
# 安装技能
openclaw skill install <skill-name>
openclaw skill install google-calendar

# 检查技能依赖
openclaw skill check <skill-name>
openclaw skill check google-calendar

# 列出已安装技能
openclaw skill list

# 卸载技能
openclaw skill uninstall <skill-name>
```

### 6. 诊断与维护命令

| 命令 | 描述 | 常用示例 |
|------|------|----------|
| `openclaw doctor` | 全面健康检查与修复 | `openclaw doctor --fix` |
| `openclaw doctor --yes` | 自动确认修复 | `openclaw doctor --yes` |
| `openclaw update` | 更新 OpenClaw 版本 | `openclaw update --channel stable` |
| `openclaw logs` | 查看网关日志 | `openclaw logs --follow` |
| `openclaw status` | 查看整体状态 | `openclaw status` |
| `openclaw security audit` | 安全审计 | `openclaw security audit --deep` |
| `openclaw security audit --fix` | 自动修复安全问题 | `openclaw security audit --fix` |

### 7. 聊天窗口命令（斜杠命令）

在与 AI 的聊天窗口中（如 Telegram、Web 界面）使用的命令：

| 命令 | 描述 |
|------|------|
| `/new [model]` | 开启全新对话，可指定模型 |
| `/status` | 查看当前状态（模型、Token 用量、成本） |
| `/model <name>` | 动态切换模型 |
| `/model list` | 查看可用模型列表 |
| `/compact` | 压缩上下文 |
| `/usage` | 查看详细用量 |
| `/exec` | 控制命令执行权限 |
| `/approve` | 批准操作 |
| `/elevated` | 提升权限模式 |
| `/help` | 查看所有斜杠命令 |

---

## 二、配置文件详解

### 2.1 配置文件位置

- 默认位置：`~/.openclaw/openclaw.json`
- 配置优先级：**环境变量 > 配置文件 > 默认值**

### 2.2 Gateway 配置

```json5
{
  "gateway": {
    "mode": "local",           // local | remote
    "port": 18789,            // 端口号
    "bind": "loopback",       // 绑定地址
    "auth": {
      "mode": "token",         // token | password | trusted-proxy
      "token": "your-token",  // 网关认证令牌
      "password": "your-password",  // 或使用 OPENCLAW_GATEWAY_PASSWORD 环境变量
      "allowTailscale": true,
      "rateLimit": {
        "maxAttempts": 10,    // 最大尝试次数
        "windowMs": 60000,     // 时间窗口（毫秒）
        "lockoutMs": 300000,   // 锁定时间（毫秒）
        "exemptLoopback": true // 豁免本地连接
      }
    },
    "tailscale": {
      "mode": "off",           // off | serve | funnel
      "resetOnExit": false
    },
    "controlUi": {
      "enabled": true,
      "basePath": "/openclaw"
    },
    "remote": {
      "url": "ws://gateway.tailnet:18789",
      "transport": "ssh",     // ssh | direct
      "token": "your-token"
    },
    "logging": {
      "redactSensitive": true // 自动脱敏日志
    },
    "tools": {
      "deny": ["browser"],     // 禁止通过 HTTP 访问的工具
      "allow": ["gateway"]    // 允许的工具
    }
  }
}
```

### 2.3 Channel 配置

```json5
{
  "channels": {
    "whatsapp": {
      "dmPolicy": "pairing",   // pairing | allowlist | open | disabled
      "allowFrom": ["+15551234567"],
      "groupPolicy": "allowlist",
      "groupAllowFrom": ["+15551234567"]
    },
    "telegram": {
      "enabled": true,
      "botToken": "123456:ABCDEF",
      "dmPolicy": "pairing"
    },
    "discord": {
      "token": "your-discord-bot-token"
    },
    "slack": {
      "botToken": "xoxb-...",
      "appToken": "xapp-..."
    }
  },
  "session": {
    "dmScope": "per-channel-peer",
    "reset": {
      "mode": "daily",
      "atHour": 4,
      "idleMinutes": 120
    }
  }
}
```

### 2.4 Skills 配置

```json5
{
  "skills": {
    "entries": {
      "google-calendar": {
        "enabled": true,
        "env": {
          "GOOGLE_CALENDAR_API_KEY": "your-key"
        },
        "config": {
          "endpoint": "https://example.com"
        }
      },
      "exec": {
        "enabled": false  // 高风险技能，建议禁用
      }
    },
    "allowBundled": ["peekaboo", "summarize"],
    "load": {
      "watch": true,
      "watchDebounceMs": 250,
      "extraDirs": ["~/shared-skills"]
    },
    "install": {
      "nodeManager": "pnpm"  // npm | pnpm | yarn | bun
    }
  }
}
```

### 2.5 Provider 配置

```json5
{
  "models": {
    "providers": {
      "anthropic": {
        "apiKey": "sk-ant-..."  // 建议使用环境变量 ANTHROPIC_API_KEY
      },
      "openai": {
        "apiKey": "sk-..."     // 建议使用环境变量 OPENAI_API_KEY
      },
      "bailian": {
        "apiKey": "your-bailian-api-key",
        "timeout": 30
      }
    }
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "model": {
        "primary": "anthropic/claude-sonnet-4-5",
        "fallbacks": ["openai/gpt-5.2"]
      },
      "models": {
        "anthropic/claude-sonnet-4-5": { "alias": "Sonnet" }
      },
      "heartbeat": {
        "every": "2h"
      }
    },
    "list": [
      {
        "id": "agent-1",
        "tools": {
          "exec": { "node": "node-id-or-name" }
        }
      }
    ]
  }
}
```

**本地模型配置：**

```json5
{
  "models": {
    "providers": {
      "local": {
        "type": "openai-compatible",
        "baseURL": "http://localhost:1234/v1",
        "modelId": "llama-3.1-8b"
      }
    }
  }
}
```

**MCP 服务器配置（2026 新功能）：**

```json5
{
  "models": {
    "mcpServers": {
      "onesearch": {
        "command": "npx",
        "args": ["-y", "@onesearch/mcp-server"]
      }
    }
  }
}
```

### 2.6 Security 配置

```json5
{
  "security": {
    "sandbox": {
      "enabled": true,
      "skills": ["exec", "browser"]
    }
  }
}
```

---

## 三、常见错误及解决方案

### 3.1 认证相关错误

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `Authentication failed` | Token 不匹配 | 检查 `gateway.auth.token` 是否与输入一致，注意空格和换行符 |
| `refusing to bind gateway ... without auth` | 未设置认证令牌 | 必须设置 `gateway.auth.token` 或 `gateway.auth.password` |
| `Invalid authentication token` | Token 格式错误 | 使用 `openssl rand -hex 32` 生成新 Token |

### 3.2 端口相关错误

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `Error: listen EADDRINUSE :::18789` | 端口被占用 | 更改端口号或杀死占用进程 `lsof -i :18789` |
| `Gateway start blocked: set gateway.mode=local` | 模式配置错误 | 在配置中设置 `"gateway": {"mode": "local"}` |

### 3.3 配置格式错误

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `SyntaxError: Unexpected token } in JSON` | JSON 格式错误 | 检查是否有多余的逗号、引号不匹配 |
| `SyntaxError: Unexpected token in JSON` | 注释格式错误 | JSON 不支持注释，移除 `//` 或 `/* */` 注释 |

**验证 JSON 格式：**
```bash
cat ~/.openclaw/openclaw.json | python -m json.tool
```

### 3.4 技能加载错误

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `Skill 'xxx' failed to load` | 技能依赖缺失 | 运行 `openclaw skill check <skill-name>` 检查依赖 |
| `bin: gcalcli not found` | 二进制程序未安装 | 安装缺失的依赖程序 |
| `env: GOOGLE_CALENDAR_API_KEY not set` | 环境变量未设置 | 在技能配置中设置 `env` 字段 |

### 3.5 通道连接错误

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `Channel whatsapp not connected` | WhatsApp 未配对 | 运行 `openclaw channels login --channel whatsapp` |
| `Invalid bot token` | Telegram Bot Token 错误 | 检查 `channels.telegram.botToken` 配置 |
| `Guild messages blocked` | Discord 消息被阻止 | 检查 `openclaw channels status --probe` |

### 3.6 安全审计错误

运行 `openclaw security audit --deep` 可能报告以下问题：

| 问题 | 严重程度 | 解决方案 |
|------|----------|----------|
| Token 强度不足 | 高 | 使用 `openssl rand -hex 32` 生成强 Token |
| 端口暴露在公网 | 高 | 配置防火墙，只允许本地访问 |
| 文件权限过于宽松 | 中 | `chmod 700 ~/.openclaw` 和 `chmod 600 ~/.openclaw/openclaw.json` |
| 高风险技能已启用 | 中 | 禁用 `exec`、`browser` 等高风险技能 |
| DM 策略不安全 | 高 | 使用 `pairing` 或 `allowlist` 模式 |

---

## 四、调试命令汇总

```bash
# 查看服务状态
openclaw status
openclaw gateway status

# 健康检查
openclaw doctor
openclaw doctor --fix

# 详细日志
openclaw logs --follow
openclaw gateway --verbose

# 通道诊断
openclaw channels status --probe

# 技能诊断
openclaw skill check <skill-name>
openclaw skill list

# 安全审计
openclaw security audit
openclaw security audit --deep
openclaw security audit --fix

# 配置验证
openclaw config validate
```

---

## 五、快速启动组合

```bash
# 1. 安装
curl -fsSL https://openclaw.ai/install.sh | bash

# 2. 配置向导
openclaw onboard --install-daemon

# 3. 登录消息通道
openclaw channels login --channel whatsapp

# 4. 查看状态
openclaw gateway status

# 5. 开始对话
openclaw tui
# 或访问 http://127.0.0.1:18789
```

---

## 六、文件权限设置

```bash
# 目录权限
chmod 700 ~/.openclaw

# 配置文件权限
chmod 600 ~/.openclaw/openclaw.json

# 定期备份配置
cp ~/.openclaw/openclaw.json ~/.openclaw/backup/openclaw-$(date +%Y%m%d).json
```
