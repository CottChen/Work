# Claude Code Env 安装脚本 - 问题与解决方案记录

## 项目概述

`claude_code_env.sh` 是一个用于在 Raspberry Pi/Debian 系统上自动安装和配置 Claude Code 开发环境的脚本。

---

## 问题记录

### 问题 1: nvm 安装脚本卡住

**现象**
```
🚀 Starting claude_code_env.sh
🔹 Node.js not found. Installing...
🔹 Installing Node.js on Linux...
🔹 Installing nvm (v0.40.3)...
# 此后无输出，脚本卡住
```

**原因分析**
1. 脚本使用 `curl -s https://raw.githubusercontent.com/.../install.sh | bash` 安装 nvm
2. `curl -s` 是静默模式，不显示进度
3. GitHub raw 内容在中国大陆访问不稳定，TCP 连接建立后下载缓慢或超时
4. nvm 安装脚本内部还执行 `git clone`，这一步更容易卡住

**解决方案**
1. 添加多个国内镜像源（Gitee、npmmirror 等）
2. 实现镜像速度自动检测，选择最快的镜像
3. 添加备用镜像回退机制

**修改内容**
```bash
# 添加镜像数组
declare -a NVM_MIRRORS=(
    "https://gitee.com/mirrors/nvm/raw/master|Gitee"
    "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh|GitHub"
)

# 镜像速度检测
detect_fastest_mirrors()

# 使用选中的镜像
curl -s "$SELECTED_NVM_MIRROR/install.sh" | bash
```

---

### 问题 2: NVM_NODEJS_ORG_MIRROR 环境变量问题

**现象**
```
$NVM_NODEJS_ORG_MIRROR and $NVM_IOJS_ORG_MIRROR may only contain a URL
Version '22' not found - try `nvm ls-remote` to browse available versions.
```

**原因分析**
1. nvm 的 `version_compare` 函数无法正确处理版本字符串
2. 原始脚本中使用了硬编码的镜像 URL，与动态选择的镜像变量不一致

**解决方案**
1. 确保 `NVM_NODEJS_ORG_MIRROR` 只包含基础 URL，不包含路径
2. 使用正确的镜像格式：`https://npmmirror.com/mirrors/node`

**修改内容**
```bash
# 正确的格式
NODE_MIRRORS=(
    "https://npmmirror.com/mirrors/node|npmmirror"
)

# 安装时设置
export NVM_NODEJS_ORG_MIRROR="$SELECTED_NODE_MIRROR"
```

---

### 问题 3: SSH 自动化传输和执行脚本

**现象**
- macOS 没有 `sshpass` 命令
- 无法在脚本中直接传递密码进行 SSH 连接

**原因分析**
- macOS 安全策略限制，不预装密码自动化工具
- Homebrew 也未安装

**解决方案**
1. 使用 `expect` 工具（macOS 自带）进行 SSH 自动化
2. 创建 expect 脚本处理密码交互

**修改内容**
```bash
cat << 'EOF' | expect -f -
set timeout 60
set pi_host "192.168.1.197"
set pi_pass "yahboom"

spawn scp $local_script $pi_user@$pi_host:~/
expect {
    "password:*" { send "$pi_pass\r" }
}
expect eof
EOF
```

---

### 问题 4: apt-get 锁被占用

**现象**
```
E: Could not get lock /var/lib/apt/lists/lock. It is held by process 173302 (apt-get)
E: Unable to lock directory /var/lib/apt/lists/
```

**原因分析**
- 后台有 apt-get 进程正在运行（可能是系统自动更新）
- 多个 apt 进程不能同时运行

**解决方案**
1. 等待后台进程完成（sleep 30）
2. 或者杀掉卡住的 apt 进程：`sudo killall apt-get`
3. 删除锁文件（最后手段）：`sudo rm /var/lib/apt/lists/lock`

---

### 问题 5: Happy 重复安装

**现象**
- 每次运行脚本都会重新安装 happy-coder
- 浪费时间和带宽

**解决方案**
在 `install_happy()` 函数开头添加检测：

```bash
install_happy() {
    # 检查 happy 是否已安装
    if command -v happy &>/dev/null; then
        local happy_version
        happy_version=$(happy --version 2>/dev/null || echo "unknown")
        log_success "Happy is already installed: $happy_version"
        return 0
    fi

    log_info "Installing Happy..."
    npm install -g happy-coder --registry="$SELECTED_NPM_MIRROR" || {
        log_error "Failed to install happy-coder"
        exit 1
    }
    log_success "Happy installed successfully"
}
```

---

## 经验反思

### 1. 国内网络环境适配

**教训**
- 不要假设所有用户都能稳定访问 GitHub、npmjs.com 等境外服务
- 中国大陆用户安装开发工具时，网络问题是首要障碍

**最佳实践**
```bash
# 始终提供国内镜像选项
# 自动检测并选择最快的镜像
# 提供手动指定镜像的参数
```

### 2. 脚本的幂等性

**教训**
- 安装脚本应该可以重复执行
- 每次执行都应该检查已安装状态
- 避免重复安装浪费资源

**最佳实践**
```bash
# 每个安装函数都先检查
if command -v xxx &>/dev/null; then
    log_success "xxx is already installed"
    return 0
fi
```

### 3. 错误处理和回退

**教训**
- 单一镜像源风险高
- 需要多个备选方案
- 失败时自动尝试下一个

**最佳实践**
```bash
# 镜像回退机制
if ! curl -s "$PRIMARY_MIRROR/install.sh" | bash; then
    for mirror in "${FALLBACK_MIRRORS[@]}"; do
        if curl -s "$mirror/install.sh" | bash; then
            break
        fi
    done
fi
```

### 4. SSH 自动化选择

**教训**
- macOS 和 Linux 工具链差异大
- `sshpass` 在 macOS 上不易安装
- `expect` 是更好的跨平台选择

**工具对比**
| 工具 | macOS | Linux | 推荐度 |
|------|-------|-------|--------|
| sshpass | 需编译安装 | 包管理器安装 | ⭐⭐ |
| expect | 系统自带 | 系统自带 | ⭐⭐⭐⭐⭐ |
| SSH Key | 需要配置 | 需要配置 | ⭐⭐⭐⭐ |

### 5. Raspberry Pi 特殊处理

**教训**
- Raspberry Pi OS 基于 Debian，但使用独立的软件源
- apt 源配置需要区分标准 Debian 和 Raspbian

**最佳实践**
```bash
# 检测 Raspberry Pi
if [ -f /etc/rpi-issue ] || grep -q "Raspberry Pi" /proc/device-tree/model; then
    # 使用 Raspbian 源
    cat > /etc/apt/sources.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ bookworm main
EOF
else
    # 使用 Debian 源
fi
```

---

## 最终安装结果

| 软件 | 版本 | 状态 |
|------|------|------|
| Node.js | v22.12.0 | ✅ |
| npm | 10.9.0 | ✅ |
| Claude Code | 2.1.71 | ✅ |
| Happy | 0.12.0 | ✅ |
| jq | 1.6 | ✅ |
| tmux | 3.3a | ✅ |
| git | 2.39.2 | ✅ |

---

## 参考资源

### 国内镜像源
- **npmmirror**: https://npmmirror.com/
- **清华镜像**: https://mirrors.tuna.tsinghua.edu.cn/
- **阿里镜像**: https://mirrors.aliyun.com/
- **中科大镜像**: https://mirrors.ustc.edu.cn/
- **腾讯镜像**: https://mirrors.cloud.tencent.com/

### 相关工具
- **nvm**: https://github.com/nvm-sh/nvm
- **expect**: 自动化交互工具
- **sshpass**: SSH 密码自动化工具
