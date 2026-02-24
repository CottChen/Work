#!/bin/bash

set -euo pipefail

# ========================
#       常量定义
# ========================
SCRIPT_NAME=$(basename "$0")
NODE_MIN_VERSION=22
NODE_INSTALL_VERSION=22
NVM_VERSION="v0.40.3"
CLAUDE_PACKAGE="@anthropic-ai/claude-code"
CLAUDE_MIN_VERSION="2.1.22"
CONFIG_DIR="$HOME/.claude"
CONFIG_FILE="$CONFIG_DIR/settings.json"
API_BASE_URL="https://open.bigmodel.cn/api/anthropic"
API_KEY_URL="https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys"
API_TIMEOUT_MS=3000000

# ========================
#       工具函数
# ========================

log_info() {
    echo "🔹 $*"
}

log_success() {
    echo "✅ $*"
}

log_error() {
    echo "❌ $*" >&2
}

ensure_dir_exists() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            exit 1
        }
    fi
}

# ========================
#     Node.js 安装函数
# ========================

install_nodejs() {
    local platform=$(uname -s)

    case "$platform" in
        Linux|Darwin)
            log_info "Installing Node.js on $platform..."

            # 安装 nvm
            log_info "Installing nvm ($NVM_VERSION)..."
            curl -s https://raw.githubusercontent.com/nvm-sh/nvm/"$NVM_VERSION"/install.sh | bash

            # 加载 nvm
            log_info "Loading nvm environment..."
            \. "$HOME/.nvm/nvm.sh"

            # 安装 Node.js
            log_info "Installing Node.js $NODE_INSTALL_VERSION..."
            nvm install "$NODE_INSTALL_VERSION"

            # 切换到新安装的 Node.js 版本
            log_info "Switching to Node.js $NODE_INSTALL_VERSION..."
            nvm use "$NODE_INSTALL_VERSION"

            # 获取实际安装的精确版本号
            INSTALLED_VERSION=$(node -v | sed 's/v//')

            # 设置为默认版本（使用精确版本号）
            log_info "Setting Node.js v$INSTALLED_VERSION as default..."
            nvm alias default "$INSTALLED_VERSION"

            # 验证安装
            node -v &>/dev/null || {
                log_error "Node.js installation failed"
                exit 1
            }
            log_success "Node.js installed: $(node -v)"
            log_success "npm version: $(npm -v)"

            # 安装/升级 pnpm 到最新版本
            log_info "Installing/upgrading pnpm to latest version..."
            npm install -g pnpm@latest || {
                log_error "Failed to install/upgrade pnpm"
                exit 1
            }
            log_success "pnpm installed/upgraded to: $(pnpm -v)"
            ;;
        *)
            log_error "Unsupported platform: $platform"
            exit 1
            ;;
    esac
}

# ========================
#     Node.js 检查函数
# ========================

check_nodejs() {
    if command -v node &>/dev/null; then
        current_version=$(node -v | sed 's/v//')
        major_version=$(echo "$current_version" | cut -d. -f1)

        if [ "$major_version" -ge "$NODE_MIN_VERSION" ]; then
            log_success "Node.js is already installed: v$current_version"
            return 0
        else
            log_info "Node.js v$current_version is installed but version < $NODE_MIN_VERSION. Upgrading..."
            install_nodejs
        fi
    else
        log_info "Node.js not found. Installing..."
        install_nodejs
    fi
}

# ========================
#     Claude Code 安装
# ========================

# 版本比较函数
version_compare() {
    # 检查第一个版本是否 >= 第二个版本
    local version1="$1"
    local version2="$2"

    # 移除 'v' 前缀（如果有）
    version1="${version1#v}"
    version2="${version2#v}"

    # 将版本号分割为数组
    IFS='.' read -ra v1_parts <<< "$version1"
    IFS='.' read -ra v2_parts <<< "$version2"

    # 比较每个部分
    for i in "${!v1_parts[@]}"; do
        local v1_part="${v1_parts[i]:-0}"
        local v2_part="${v2_parts[i]:-0}"

        if [ "$v1_part" -gt "$v2_part" ]; then
            return 0  # version1 > version2
        elif [ "$v1_part" -lt "$v2_part" ]; then
            return 1  # version1 < version2
        fi
    done

    return 0  # version1 == version2
}

install_claude_code() {
    if command -v claude &>/dev/null; then
        current_version=$(claude --version 2>/dev/null || echo "unknown")
        log_info "Claude Code is already installed: $current_version"

        # 检查版本
        if version_compare "$current_version" "$CLAUDE_MIN_VERSION"; then
            log_success "Claude Code version $current_version meets requirement (>= $CLAUDE_MIN_VERSION)"
        else
            log_info "Claude Code version $current_version is outdated. Upgrading to $CLAUDE_MIN_VERSION..."
            npm install -g "$CLAUDE_PACKAGE@$CLAUDE_MIN_VERSION" || {
                log_error "Failed to upgrade claude-code"
                exit 1
            }
            new_version=$(claude --version 2>/dev/null || echo "unknown")
            log_success "Claude Code upgraded to: $new_version"
        fi
    else
        log_info "Installing Claude Code..."
        npm install -g "$CLAUDE_PACKAGE" || {
            log_error "Failed to install claude-code"
            exit 1
        }
        log_success "Claude Code installed successfully: $(claude --version)"
    fi
}

# ========================
#     Happy 安装
# ========================

install_happy() {
    log_info "Installing Happy..."
    npm install -g happy-coder || {
        log_error "Failed to install happy-coder"
        exit 1
    }
    log_success "Happy installed successfully"
}

configure_claude_json(){
  node --eval '
      const os = require("os");
      const fs = require("fs");
      const path = require("path");

      const homeDir = os.homedir();
      const filePath = path.join(homeDir, ".claude.json");
      if (fs.existsSync(filePath)) {
          const content = JSON.parse(fs.readFileSync(filePath, "utf-8"));
          fs.writeFileSync(filePath, JSON.stringify({ ...content, hasCompletedOnboarding: true }, null, 2), "utf-8");
      } else {
          fs.writeFileSync(filePath, JSON.stringify({ hasCompletedOnboarding: true }, null, 2), "utf-8");
      }'
}

# ========================
#     API Key 配置
# ========================

configure_claude() {
    log_info "Configuring Claude Code..."
    echo "   You can get your API key from: $API_KEY_URL"
    read -s -p "🔑 Please enter your ZHIPU API key: " api_key
    echo

    if [ -z "$api_key" ]; then
        log_error "API key cannot be empty. Please run the script again."
        exit 1
    fi

    ensure_dir_exists "$CONFIG_DIR"

    # 写入配置文件
    node --eval '
        const os = require("os");
        const fs = require("fs");
        const path = require("path");

        const homeDir = os.homedir();
        const filePath = path.join(homeDir, ".claude", "settings.json");
        const apiKey = "'"$api_key"'";

        const content = fs.existsSync(filePath)
            ? JSON.parse(fs.readFileSync(filePath, "utf-8"))
            : {};

        fs.writeFileSync(filePath, JSON.stringify({
            ...content,
            env: {
                ANTHROPIC_AUTH_TOKEN: apiKey,
                ANTHROPIC_BASE_URL: "'"$API_BASE_URL"'",
                API_TIMEOUT_MS: "'"$API_TIMEOUT_MS"'",
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: 1,
                ANTHROPIC_MODEL: "GLM-4.7",
                ANTHROPIC_SMALL_FAST_MODEL: "GLM-4.7",
                ANTHROPIC_DEFAULT_SONNET_MODEL: "GLM-4.7",
                ANTHROPIC_DEFAULT_OPUS_MODEL: "GLM-4.7",
                ANTHROPIC_DEFAULT_HAIKU_MODEL: "GLM-4.5-Air"
            }
        }, null, 2), "utf-8");
    ' || {
        log_error "Failed to write settings.json"
        exit 1
    }

    log_success "Claude Code configured successfully"
}

# ========================
#     jq 安装函数
# ========================

install_jq() {
    if command -v jq &>/dev/null; then
        log_success "jq is already installed: $(jq --version)"
        return 0
    fi

    local platform=$(uname -s)

    case "$platform" in
        Linux)
            log_info "Installing jq on Linux..."

            # 检测 Linux 发行版
            if [ -f /etc/debian_version ]; then
                # Debian/Ubuntu
                log_info "Updating apt-get package list..."
                sudo apt-get update
                log_info "Installing jq..."
                sudo apt-get install -y jq
            elif [ -f /etc/redhat-release ]; then
                # RHEL/CentOS/Fedora
                sudo yum install -y jq || sudo dnf install -y jq
            elif [ -f /etc/arch-release ]; then
                # Arch Linux
                sudo pacman -S --noconfirm jq
            else
                log_error "Unsupported Linux distribution. Please install jq manually."
                exit 1
            fi
            ;;
        Darwin)
            log_info "Installing jq on macOS..."

            # 检查是否安装了 Homebrew
            if command -v brew &>/dev/null; then
                brew install jq
            else
                log_error "Homebrew not found. Please install Homebrew first: https://brew.sh"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported platform: $platform"
            exit 1
            ;;
    esac

    # 验证安装
    if command -v jq &>/dev/null; then
        log_success "jq installed successfully: $(jq --version)"
    else
        log_error "jq installation failed"
        exit 1
    fi
}

# ========================
#     Tmux 安装函数
# ========================

install_tmux() {
    if command -v tmux &>/dev/null; then
        log_success "tmux is already installed: $(tmux -V)"
        return 0
    fi

    local platform=$(uname -s)

    case "$platform" in
        Linux)
            log_info "Installing tmux on Linux..."

            # 检测 Linux 发行版
            if [ -f /etc/debian_version ]; then
                # Debian/Ubuntu
                sudo apt-get update && sudo apt-get install -y tmux
            elif [ -f /etc/redhat-release ]; then
                # RHEL/CentOS/Fedora
                sudo yum install -y tmux || sudo dnf install -y tmux
            elif [ -f /etc/arch-release ]; then
                # Arch Linux
                sudo pacman -S --noconfirm tmux
            else
                log_error "Unsupported Linux distribution. Please install tmux manually."
                exit 1
            fi
            ;;
        Darwin)
            log_info "Installing tmux on macOS..."

            # 检查是否安装了 Homebrew
            if command -v brew &>/dev/null; then
                brew install tmux
            else
                log_error "Homebrew not found. Please install Homebrew first: https://brew.sh"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported platform: $platform"
            exit 1
            ;;
    esac

    # 验证安装
    if command -v tmux &>/dev/null; then
        log_success "tmux installed successfully: $(tmux -V)"
    else
        log_error "tmux installation failed"
        exit 1
    fi
}

# ========================
#     Git 安装函数
# ========================

install_git() {
    if command -v git &>/dev/null; then
        log_success "Git is already installed: $(git --version)"
        return 0
    fi

    local platform=$(uname -s)

    case "$platform" in
        Linux)
            log_info "Installing Git on Linux..."

            # 检测 Linux 发行版
            if [ -f /etc/debian_version ]; then
                # Debian/Ubuntu
                sudo apt-get update && sudo apt-get install -y git
            elif [ -f /etc/redhat-release ]; then
                # RHEL/CentOS/Fedora
                sudo yum install -y git || sudo dnf install -y git
            elif [ -f /etc/arch-release ]; then
                # Arch Linux
                sudo pacman -S --noconfirm git
            else
                log_error "Unsupported Linux distribution. Please install Git manually."
                exit 1
            fi
            ;;
        Darwin)
            log_info "Installing Git on macOS..."

            # 检查是否安装了 Homebrew
            if command -v brew &>/dev/null; then
                brew install git
            else
                # macOS 通常自带 Git，如果不存在则提示用户安装
                log_error "Git not found. Please install Git via: xcode-select --install"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported platform: $platform"
            exit 1
            ;;
    esac

    # 验证安装
    if command -v git &>/dev/null; then
        log_success "Git installed successfully: $(git --version)"
    else
        log_error "Git installation failed"
        exit 1
    fi
}

# ========================
#     Git 配置函数
# ========================

configure_git() {
    log_info "Configuring Git..."

    # 检查是否已配置
    if git config --global user.name &>/dev/null && git config --global user.email &>/dev/null; then
        log_success "Git is already configured:"
        echo "   User: $(git config --global user.name)"
        echo "   Email: $(git config --global user.email)"
        return 0
    fi

    # 提示用户输入
    read -p "👤 Please enter your Git user name: " git_name
    read -p "📧 Please enter your Git user email: " git_email

    if [ -z "$git_name" ] || [ -z "$git_email" ]; then
        log_error "Git name and email cannot be empty"
        exit 1
    fi

    git config --global user.name "$git_name"
    git config --global user.email "$git_email"

    # Git 中文配置
    git config --global core.quotePath false
    git config --global i18n.commitencoding utf-8
    git config --global i18n.logoutputencoding utf-8
    git config --global gui.encoding utf-8

    log_success "Git configured successfully:"
    echo "   User: $git_name"
    echo "   Email: $git_email"
}

# ========================
#   中文 Locale 安装
# ========================

install_chinese_locale() {
    local platform=$(uname -s)

    case "$platform" in
        Linux)
            log_info "Installing Chinese locale..."
            # 检测 Linux 发行版
            if [ -f /etc/debian_version ]; then
                # Debian/Ubuntu
                sudo apt-get update
                sudo apt-get install -y locales
                sudo sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
                sudo sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
                sudo locale-gen
                sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
                log_success "Chinese locale installed"
            else
                log_info "Non-Debian Linux. Please configure locale manually."
            fi
            ;;
        Darwin)
            log_info "macOS already supports Chinese locale by default"
            ;;
        *)
            log_error "Unsupported platform: $platform"
            ;;
    esac
}

# ========================
#   Vim 配置函数
# ========================

configure_vim() {
    local vimrc_file="$HOME/.vimrc"

    log_info "Configuring Vim for Chinese..."

    # 检查是否已存在中文配置
    if [ -f "$vimrc_file" ] && grep -q "encoding=utf-8" "$vimrc_file" 2>/dev/null; then
        log_success "Vim Chinese configuration already exists"
        return 0
    fi

    # 创建或追加 .vimrc
    if [ ! -f "$vimrc_file" ]; then
        touch "$vimrc_file"
    fi

    # 追加中文配置
    cat >> "$vimrc_file" << 'EOF'

" Chinese encoding support
set encoding=utf-8
set termencoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8,ucs-bom,gb18030,gbk,gb2312,cp936
EOF

    log_success "Vim configured for Chinese"
}

# ========================
#   Bashrc 配置函数
# ========================

configure_bashrc() {
    local bashrc_file="$HOME/.bashrc"
    local alias_command="alias claude-go='claude --dangerously-skip-permissions'"

    log_info "Configuring ~/.bashrc..."

    # 检查是否已存在该别名
    if [ -f "$bashrc_file" ] && grep -q "claude-go" "$bashrc_file" 2>/dev/null; then
        log_success "Alias 'claude-go' already exists in ~/.bashrc"
        return 0
    fi

    # 创建 .bashrc 如果不存在
    if [ ! -f "$bashrc_file" ]; then
        touch "$bashrc_file"
    fi

    # 添加别名
    echo "" >> "$bashrc_file"
    echo "# Claude Code quick command" >> "$bashrc_file"
    echo "$alias_command" >> "$bashrc_file"

    source ~/.bashrc
    log_success "Alias 'claude-go' added to ~/.bashrc"
}

# ========================
#   Tmux 配置函数
# ========================

configure_tmux() {
    local tmux_conf="$HOME/.tmux.conf"

    log_info "Configuring tmux..."

    # 创建 tmux 配置文件
    if [ ! -f "$tmux_conf" ]; then
        touch "$tmux_conf"
    fi

    # 检查配置是否已存在
    if grep -q "set -g mouse on" "$tmux_conf" 2>/dev/null; then
        log_success "tmux configuration already exists"
        return 0
    fi

    # 添加 tmux 配置
    cat >> "$tmux_conf" << 'EOF'

# ========================
# tmux configuration
# ========================

# 1. 启用鼠标支持，允许tmux拦截并处理鼠标滚动事件
set -g mouse on

# 2. 覆盖终端能力，禁用备用屏幕缓冲切换。这是解决大多数"附加后无法滚动"问题的关键。
#    适用于以 `xterm` 开头的 $TERM (如 xterm-256color)。
set -g terminal-overrides 'xterm*:smcup@:rmcup@'
#    更通用的写法，覆盖更多终端类型：
# set -g terminal-overrides 'xterm*:smcup@:rmcup@,screen*:smcup@:rmcup@'

# 3. (可选但推荐) 设置一个较大的历史限制，确保有足够的历史可查看。
set -g history-limit 10000

# 4. 设置默认的终端类型，确保tmux内部程序（如vim）使用正确的颜色和支持。
set -g default-terminal "screen-256color"
# 或根据你的终端使用 "tmux-256color" (如果终端支持且tmux版本较新)
# set -g default-terminal "tmux-256color"
EOF

    # 使配置生效
    tmux source-file "$tmux_conf" 2>/dev/null || {
        log_info "tmux is not running, configuration will take effect on next tmux start"
    }

    log_success "tmux configured successfully"
}

# ========================
#   项目初始化函数
# ========================

init_project() {
    local project_dir="$HOME/project"

    log_info "Initializing project directory..."

    # 创建项目目录
    ensure_dir_exists "$project_dir"

    # 切换到项目目录
    cd "$project_dir" || {
        log_error "Failed to change to project directory: $project_dir"
        exit 1
    }

    # 初始化 Git 仓库（如果尚未初始化）
    if [ ! -d ".git" ]; then
        log_info "Initializing Git repository..."
        git init
        log_success "Git repository initialized"
    else
        log_success "Git repository already exists"
    fi

    # 创建 .gitignore 文件
    if [ ! -f ".gitignore" ]; then
        log_info "Creating .gitignore file..."
        cat > .gitignore << 'EOF'
# OS files
.DS_Store
Thumbs.db

# Temporary files
*.tmp
.temp/

# Node modules (if using Node.js projects)
node_modules/

# Next build (if using Next projects)
.next/

# Python cache (if using Python projects)
__pycache__/
*.pyc

# Rust build (if using Rust projects)
target/

# IDE files
.vscode/
.idea/
*.swp
*.swo
EOF
        log_success ".gitignore file created"
    else
        log_info ".gitignore already exists, skipping..."
    fi

    log_success "Project directory ready: $project_dir"
}

# ========================
#        主流程
# ========================

main() {
    echo "🚀 Starting $SCRIPT_NAME"

    check_nodejs
    install_claude_code
    install_happy
    configure_claude_json
    configure_claude
    install_jq
    install_tmux
    configure_tmux
    install_chinese_locale
    configure_bashrc
    install_git
    configure_git
    configure_vim
    init_project

    echo ""
    log_success "🎉 Installation completed successfully!"
    echo ""
    echo "🚀 You can now start using Claude Code with:"
    echo "   claude"
    echo ""
    echo "⚡ Quick command (after 'source ~/.bashrc'):"
    echo "   claude-go"
    echo ""
    echo "📁 Project directory: $HOME/project"
}

main "$@"
