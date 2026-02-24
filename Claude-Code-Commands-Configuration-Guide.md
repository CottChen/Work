# Claude Code 命令与配置完整指南

本文档详细介绍 Claude Code 的所有 CLI 命令、配置参数，以及常见的配置项。

---

## 一、CLI 命令详解

### 1.1 核心命令

| 命令 | 描述 | 示例 |
|------|------|------|
| `claude` | 启动交互式 REPL | `claude` |
| `claude "query"` | 使用初始提示启动 REPL | `claude "解释这个项目"` |
| `claude -p "query"` | 非交互式查询，然后退出 | `claude -p "审查这段代码"` |
| `claude -c` | 继续最近的对话 | `claude -c` |
| `claude -c -p "query"` | 在打印模式下继续 | `claude -c -p "运行测试"` |
| `claude -r "id" "query"` | 通过会话 ID 恢复对话 | `claude -r "abc123" "完成 PR"` |
| `claude --help` | 显示帮助信息 | `claude --help` |
| `claude --version` | 显示版本号 | `claude --version` |

### 1.2 配置管理命令

```bash
# 列出所有设置
claude config list

# 查看特定设置
claude config get <key>
claude config get model
claude config get theme

# 修改设置（项目级）
claude config set <key> <value>
claude config set theme dark
claude config set model claude-sonnet-4-5
claude config set autoUpdates false

# 修改设置（全局）
claude config set -g <key> <value>
claude config set -g theme dark

# 追加设置（列表类型）
claude config add <key> <value>
claude config add allowedTools "Bash"

# 删除设置（列表类型）
claude config remove <key> <value>
```

### 1.3 MCP 服务器命令

```bash
# 查看 MCP 帮助
claude mcp --help

# 列出已配置的 MCP 服务器
claude mcp list

# 添加 MCP 服务器
claude mcp add <name> <commandOrUrl> [args...]
claude mcp add filesystem "npx" "-y" "@modelcontextprotocol/server-filesystem" "/path/to/dir"

# 添加 MCP 服务器（JSON 格式）
claude mcp add-json <name> <json>
claude mcp add-json myserver '{"command":"node","args":["server.js"]}'

# 从 Claude Desktop 导入（MCP 和 WSL 仅限 Mac）
claude mcp add-from-claude-desktop

# 移除 MCP 服务器
claude mcp remove <name>

# 重置项目级 MCP 选择
claude mcp reset-project-choices
```

### 1.4 其他命令

```bash
# 检查更新
claude update
claude update --channel stable

# 健康检查
claude doctor

# 安装 Claude Code
claude install
claude install stable
claude install latest
claude install 1.0.0

# 设置认证令牌
claude setup-token

# 迁移安装程序
claude migrate-installer
```

### 1.5 CLI 选项参数

| 选项 | 描述 | 示例 |
|------|------|------|
| `-p, --print` | 非交互式模式 | `claude -p "query"` |
| `-r, --resume <id>` | 通过会话 ID 恢复对话 | `claude -r abc123` |
| `-c, --continue` | 继续最近对话 | `claude -c` |
| `--output-format <format>` | 输出格式 (text/json/stream-json) | `claude -p --output-format json` |
| `--verbose` | 启用详细日志 | `claude --verbose` |
| `--max-turns <n>` | 限制交互轮次 | `claude --max-turns 3` |
| `--system-prompt <text>` | 覆盖系统提示（仅与 --print 配合） | `claude -p --system-prompt "自定义指令"` |
| `--add-dir <path>` | 添加额外工作目录 | `claude --add-dir ../docs` |
| `--dangerously-skip-permissions` | 跳过所有权限检查（危险） | `claude --dangerously-skip-permissions` |
| `--allowed-tools <tools>` | 允许的工具列表 | `claude --allowedTools "Edit,View"` |
| `--disallowed-tools <tools>` | 禁止的工具列表 | `claude --disallowed-tools "WebFetch"` |
| `--model <model>` | 指定使用模型 | `claude --model opus` |
| `--print-only` | 只打印响应，不执行工具 | `claude --print-only` |
| `--skip-net-bypass` | 跳过网络绕过 | `claude --skip-net-bypass` |

---

## 二、配置文件详解

### 2.1 配置文件位置

Claude Code 使用分层配置系统：

| 级别 | 位置 | 说明 |
|------|------|------|
| 用户级 | `~/.claude/settings.json` | 适用于所有项目 |
| 项目级（共享） | `.claude/settings.json` | 纳入版本控制，团队共享 |
| 项目级（本地） | `.claude/settings.local.json` | 不纳入版本控制 |
| 企业级 | `/etc/claude-code/managed-settings.json` (Linux) | 企业策略，不可覆盖 |

**配置优先级（从高到低）：**
1. 企业策略 (managed-settings.json)
2. 命令行参数
3. 本地项目设置 (.claude/settings.local.json)
4. 共享项目设置 (.claude/settings.json)
5. 用户设置 (~/.claude/settings.json)

### 2.2 settings.json 配置项

```json5
{
  // ===== 模型配置 =====
  "model": "claude-sonnet-4-5-20241022",
  "model": "claude-opus-4-5-20251101",
  "model": "claude-3-5-sonnet-20241022",
  "model": "claude-3-5-haiku-20241022",

  // ===== 显示配置 =====
  "theme": "dark",
  "theme": "light",
  "theme": "light-daltonized",
  "theme": "dark-daltonized",

  "verbose": true,

  "preferredNotifChannel": "iterm2",
  "preferredNotifChannel": "iterm2_with_bell",
  "preferredNotifChannel": "terminal_bell",
  "preferredNotifChannel": "notifications_disabled",

  // ===== 自动更新 =====
  "autoUpdates": true,
  "autoUpdates": false,

  // ===== 工具配置 =====
  "allowedTools": ["Edit", "View", "Bash(git:*)"],
  "disallowedTools": ["WebFetch", "WebSearch"],

  // ===== 权限配置 =====
  "permissions": {
    "allow": [
      "Bash(npm run *)",
      "Bash(git commit *)",
      "Bash(pnpm test)",
      "Read(~/.zshrc)"
    ],
    "deny": [
      "Bash(curl:*)",
      "Bash(wget:*)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "WebFetch",
      "Task(Explore)"
    ],
    "ask": [
      "Bash"
    ],
    "additionalDirectories": [
      "../docs/"
    ],
    "defaultMode": "acceptEdits",
    "defaultMode": "default",
    "defaultMode": "plan",
    "defaultMode": "dontAsk",
    "defaultMode": "bypassPermissions",
    "disableBypassPermissionsMode": "disable"
  },

  // ===== 环境变量 =====
  "env": {
    "FOO": "bar",
    "API_KEY": "your-key"
  },

  // ===== Hooks 配置 =====
  "hooks": {
    "PreToolUse": {
      "Bash": "echo 'Running command...'"
    },
    "PostToolUse": {
      "Edit": "echo 'File edited'"
    }
  },

  // ===== MCP 配置 =====
  "enableAllProjectMcpServers": true,
  "enabledMcpjsonServers": ["memory", "github"],
  "disabledMcpjsonServers": ["filesystem"],

  // ===== 其他配置 =====
  "apiKeyHelper": "/bin/generate_temp_api_key.sh",
  "cleanupPeriodDays": 30,
  "includeCoAuthoredBy": true,
  "forceLoginMethod": "claudeai",
  "forceLoginMethod": "console",

  // ===== AWS 配置 =====
  "awsAuthRefresh": "aws sso login --profile myprofile",
  "awsCredentialExport": "/bin/generate_aws_grant.sh"
}
```

---

## 三、权限系统详解

### 3.1 权限模式

| 模式 | 描述 |
|------|------|
| `default` | 标准行为：首次使用每个工具时提示权限 |
| `acceptEdits` | 自动接受文件编辑权限 |
| `plan` | 计划模式：只能分析，不能修改文件或执行命令 |
| `delegate` | 协调模式：仅用于代理团队管理 |
| `dontAsk` | 自动拒绝工具，除非通过 permissions.allow 预批准 |
| `bypassPermissions` | 跳过所有权限检查（仅在安全环境使用） |

### 3.2 权限规则语法

**基本语法：**
```json
{
  "permissions": {
    "allow": ["Tool", "Tool(specifier)"],
    "deny": ["Tool", "Tool(specifier)"],
    "ask": ["Tool", "Tool(specifier)"]
  }
}
```

**规则评估顺序：** deny -> ask -> allow（匹配到的第一条规则生效）

### 3.3 工具权限规则

| 规则 | 效果 |
|------|------|
| `Bash` | 匹配所有 Bash 命令 |
| `WebFetch` | 匹配所有网页获取请求 |
| `Read` | 匹配所有文件读取 |
| `Edit` | 匹配所有文件编辑 |
| `Write` | 匹配所有文件写入 |

### 3.4 通配符模式

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run *)",        // 匹配 npm run build, npm run test 等
      "Bash(git commit *)",      // 匹配 git commit -m "..." 等
      "Bash(git * main)",        // 匹配 git checkout main, git merge main 等
      "Bash(* --version)",       // 匹配任何 --version 命令
      "Bash(* --help *)"         // 匹配任何 --help 命令
    ],
    "deny": [
      "Bash(git push *)",        // 阻止 git push 命令
      "Bash(curl:*)",            // 阻止 curl 命令
      "Bash(wget:*)"            // 阻止 wget 命令
    ]
  }
}
```

### 3.5 文件路径规则

| 模式 | 含义 | 示例 | 匹配 |
|------|------|------|------|
| `//path` | 绝对路径 | `Read(//Users/alice/secrets/**)` | `/Users/alice/secrets/**` |
| `~/path` | 主目录路径 | `Read(~/Documents/*.pdf)` | `/Users/alice/Documents/*.pdf` |
| `/path` | 相对于配置文件 | `Edit(/src/**/*.ts)` | `<settings>/src/**/*.ts` |
| `path` 或 `./path` | 相对于当前目录 | `Read(*.env)` | `<cwd>/*.env` |

### 3.6 WebFetch 规则

```json
{
  "permissions": {
    "allow": [
      "WebFetch(domain:example.com)",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:*.anthropic.com)"
    ],
    "deny": [
      "WebFetch"
    ]
  }
}
```

### 3.7 MCP 工具规则

```json
{
  "permissions": {
    "allow": [
      "mcp__puppeteer",                    // 匹配 puppeteer 服务器的所有工具
      "mcp__puppeteer__*",                  // 通配符语法
      "mcp__puppeteer__puppeteer_navigate" // 匹配特定工具
    ],
    "deny": [
      "mcp__filesystem"                    // 阻止文件系统 MCP
    ]
  }
}
```

### 3.8 子代理 (Subagent) 规则

```json
{
  "permissions": {
    "deny": [
      "Task(Explore)",      // 禁用 Explore 子代理
      "Task(Plan)",         // 禁用 Plan 子代理
      "Task(my-custom-agent)"  // 禁用自定义子代理
    ]
  }
}
```

---

## 四、环境变量详解

### 4.1 认证相关

| 环境变量 | 用途 |
|----------|------|
| `ANTHROPIC_API_KEY` | API 密钥，作为 X-Api-Key 头发送 |
| `ANTHROPIC_AUTH_TOKEN` | 自定义授权头值（会被添加 Bearer 前缀） |
| `ANTHROPIC_CUSTOM_HEADERS` | 自定义请求头（格式：Name: Value） |
| `ANTHROPIC_MODEL` | 指定自定义模型 |
| `ANTHROPIC_SMALL_FAST_MODEL` | Haiku 类模型用于后台任务 |
| `ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION` | 使用 Bedrock 时的小模型 AWS 区域 |

### 4.2 模型提供商

| 环境变量 | 用途 |
|----------|------|
| `CLAUDE_CODE_USE_BEDROCK` | 使用 Bedrock |
| `CLAUDE_CODE_USE_VERTEX` | 使用 Vertex |
| `CLAUDE_CODE_SKIP_BEDROCK_AUTH` | 跳过 Bedrock AWS 认证 |
| `CLAUDE_CODE_SKIP_VERTEX_AUTH` | 跳过 Vertex Google 认证 |
| `AWS_BEARER_TOKEN_BEDROCK` | Bedrock API 密钥 |
| `VERTEX_REGION_CLAUDE_3_5_HAIKU` | Claude 3.5 Haiku 的 Vertex 区域 |
| `VERTEX_REGION_CLAUDE_3_5_SONNET` | Claude 3.5 Sonnet 的 Vertex 区域 |
| `VERTEX_REGION_CLAUDE_3_7_SONNET` | Claude 3.7 Sonnet 的 Vertex 区域 |
| `VERTEX_REGION_CLAUDE_4_0_OPUS` | Claude 4.0 Opus 的 Vertex 区域 |
| `VERTEX_REGION_CLAUDE_4_0_SONNET` | Claude 4.0 Sonnet 的 Vertex 区域 |

### 4.3 Bash 命令配置

| 环境变量 | 用途 |
|----------|------|
| `BASH_DEFAULT_TIMEOUT_MS` | Bash 命令默认超时时间 |
| `BASH_MAX_TIMEOUT_MS` | Bash 命令最大超时时间 |
| `BASH_MAX_OUTPUT_LENGTH` | Bash 输出最大字符数（超过后截断） |
| `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` | 每个 Bash 命令后返回原工作目录 |

### 4.4 MCP 配置

| 环境变量 | 用途 |
|----------|------|
| `MCP_TIMEOUT` | MCP 服务器启动超时（毫秒） |
| `MCP_TOOL_TIMEOUT` | MCP 工具执行超时（毫秒） |

### 4.5 功能开关

| 环境变量 | 用途 |
|----------|------|
| `DISABLE_AUTOUPDATER` | 禁用自动更新 |
| `DISABLE_BUG_COMMAND` | 禁用 /bug 命令 |
| `DISABLE_COST_WARNINGS` | 禁用费用警告消息 |
| `DISABLE_ERROR_REPORTING` | 禁用 Sentry 错误报告 |
| `DISABLE_NON_ESSENTIAL_MODEL_CALLS` | 禁用非关键路径的模型调用 |
| `DISABLE_TELEMETRY` | 禁用 Statsig 遥测 |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | 相当于设置所有上述禁用选项 |
| `CLAUDE_CODE_DISABLE_TERMINAL_TITLE` | 禁用自动终端标题更新 |
| `CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL` | 跳过 IDE 扩展自动安装 |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | 设置最大输出 token 数 |
| `MAX_THINKING_TOKENS` | 强制思考的 token 预算 |
| `MAX_MCP_OUTPUT_TOKENS` | MCP 工具响应最大 token 数（默认 25000） |

### 4.6 网络代理

| 环境变量 | 用途 |
|----------|------|
| `HTTP_PROXY` | HTTP 代理服务器 |
| `HTTPS_PROXY` | HTTPS 代理服务器 |

---

## 五、CLAUDE.md 文件

### 5.1 文件位置与优先级

| 位置 | 说明 |
|------|------|
| `./CLAUDE.md` | 项目级，本地文件 |
| `./AGENTS.md` | 项目级，代理配置 |
| `~/.claude/CLAUDE.md` | 用户级全局规则 |

**优先级（从高到低）：**
1. 本地文件（从当前目录向上遍历）
2. 全局文件 `~/.config/opencode/AGENTS.md`
3. Claude Code 文件 `~/.claude/CLAUDE.md`

### 5.2 文件语法

CLAUDE.md 文件支持以下语法：

```markdown
# 项目规则

## 概述
这个项目是一个...

## 代码规范
- 使用 TypeScript
- 遵循 Airbnb 风格指南

## 构建命令
- 开发: npm run dev
- 构建: npm run build
- 测试: npm run test

## 注意事项
- 不要修改 config 目录下的文件
- 生产部署需要先通过测试
```

---

## 六、沙箱配置

### 6.1 沙箱配置项

```json5
{
  "sandbox": {
    "autoAllowBashIfSandboxed": false,
    "excludedCommands": [],
    "network": {
      "allowUnixSockets": [],
      "allowAllUnixSockets": false,
      "allowLocalBinding": false,
      "allowedDomains": [],
      "httpProxyPort": null,
      "socksProxyPort": null
    },
    "enableWeakerNestedSandbox": false
  }
}
```

### 6.2 沙箱与权限的配合

| 层级 | 控制方式 |
|------|----------|
| 权限 | 控制 Claude Code 可以使用哪些工具及访问哪些文件/域 |
| 沙箱 | 提供 OS 级 enforcement，限制 Bash 工具的文件系统和网络访问 |

---

## 七、子代理配置

### 7.1 子代理文件位置

| 位置 | 说明 |
|------|------|
| `~/.claude/agents/` | 用户级子代理，所有项目可用 |
| `.claude/agents/` | 项目级子代理，仅当前项目可用 |

### 7.2 子代理文件格式

```markdown
---
description: Explore subagent for codebase exploration
allowed-tools: Read,Grep,Glob,Bash,Task

You are an expert at exploring codebases...
```

---

## 八、Hooks 配置

### 8.1 Hook 类型

| Hook | 触发时机 |
|------|----------|
| `PreToolUse` | 工具执行前 |
| `PostToolUse` | 工具执行后 |

### 8.2 Hook 配置示例

```json
{
  "hooks": {
    "PreToolUse": {
      "Bash": "echo 'About to run: $TOOL_NAME'",
      "Edit": "echo 'About to edit: $TOOL_ARGUMENTS'"
    },
    "PostToolUse": {
      "Write": "echo 'Wrote to file: $TOOL_RESULT'"
    }
  }
}
```

**可用环境变量：**
- `$TOOL_NAME` - 工具名称
- `$TOOL_ARGUMENTS` - 工具参数
- `$TOOL_RESULT` - 工具执行结果

---

## 九、常见配置错误

### 9.1 权限配置错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| 权限规则不生效 | 规则语法错误 | 检查通配符和路径格式 |
| deny 规则不生效 | 规则优先级问题 | deny 规则必须在 allow 之前 |
| Windows 文件权限不生效 | 原生 Windows 限制 | 使用 WSL 或检查路径格式 |

### 9.2 MCP 配置错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| MCP 服务器无法启动 | 命令或路径错误 | 检查 command 和 args |
| MCP 工具超时 | MCP_TIMEOUT 设置过短 | 增加超时时间 |
| 环境变量未传递 | env 格式错误 | 检查 JSON 格式 |

### 9.3 模型配置错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| 模型不可用 | API 密钥未设置 | 设置 ANTHROPIC_API_KEY |
| 模型响应慢 | 网络代理问题 | 配置 HTTP_PROXY/HTTPS_PROXY |

---

## 十、快速配置示例

### 10.1 基础配置

```json
{
  "model": "claude-sonnet-4-5",
  "theme": "dark",
  "autoUpdates": true
}
```

### 10.2 严格安全配置

```json
{
  "permissions": {
    "disableBypassPermissionsMode": "disable",
    "allow": [
      "Bash(npm run *)",
      "Bash(git *)",
      "Read",
      "Edit"
    ],
    "deny": [
      "WebFetch",
      "WebSearch",
      "Bash(curl:*)",
      "Bash(wget:*)",
      "Task(Explore)"
    ],
    "defaultMode": "default"
  }
}
```

### 10.3 MCP 配置

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"],
      "env": {}
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

### 10.4 带 Hook 的配置

```json
{
  "hooks": {
    "PreToolUse": {
      "Bash": "echo '[PreToolUse] Running: $TOOL_NAME with: $TOOL_ARGUMENTS'"
    },
    "PostToolUse": {
      "Bash": "echo '[PostToolUse] Completed: $TOOL_NAME'"
    }
  }
}
```
