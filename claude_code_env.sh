#!/bin/bash

set -euo pipefail

# ========================
#       常量定义
# ========================
SCRIPT_NAME=$(basename "$0")
NODE_MIN_VERSION=18
NODE_INSTALL_VERSION=22
NVM_VERSION="v0.40.3"
CLAUDE_PACKAGE="@anthropic-ai/claude-code"
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

            # 验证安装
            node -v &>/dev/null || {
                log_error "Node.js installation failed"
                exit 1
            }
            log_success "Node.js installed: $(node -v)"
            log_success "npm version: $(npm -v)"
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

install_claude_code() {
    if command -v claude &>/dev/null; then
        log_success "Claude Code is already installed: $(claude --version)"
    else
        log_info "Installing Claude Code..."
        npm install -g "$CLAUDE_PACKAGE" || {
            log_error "Failed to install claude-code"
            exit 1
        }
        log_success "Claude Code installed successfully"
    fi
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

    log_success "Git configured successfully:"
    echo "   User: $git_name"
    echo "   Email: $git_email"
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
    configure_claude_json
    configure_claude
    configure_bashrc
    install_git
    configure_git
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
