#!/bin/bash

set -euo pipefail

# ========================
#       常量定义
# ========================
SCRIPT_NAME=$(basename "$0")
NODE_MIN_VERSION=24
NODE_INSTALL_VERSION=24
NVM_VERSION="v0.40.3"

# 国内镜像配置 - 多个镜像源
declare -a NVM_MIRRORS=(
    "https://gitee.com/mirrors/nvm/raw/master|Gitee"
    "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh|GitHub"
)
declare -a NODE_MIRRORS=(
    "https://npmmirror.com/mirrors/node|npmmirror"
    "https://mirrors.cloud.tencent.com/nodejs-release/|Tencent"
    "https://mirrors.aliyun.com/nodejs-release/|Aliyun"
)
declare -a NPM_MIRRORS=(
    "https://registry.npmmirror.com|npmmirror"
    "https://registry.npm.taobao.org|Taobao"
)
declare -a APT_MIRRORS=(
    "https://mirrors.tuna.tsinghua.edu.cn|Tsinghua"
    "https://mirrors.aliyun.com|Aliyun"
    "https://mirrors.ustc.edu.cn|USTC"
    "https://mirrors.cloud.tencent.com|Tencent"
)

# 选中的最快镜像
SELECTED_NVM_MIRROR=""
SELECTED_NODE_MIRROR=""
SELECTED_NPM_MIRROR=""
SELECTED_APT_MIRROR=""
SELECTED_NVM_MIRROR_NAME=""
SELECTED_NODE_MIRROR_NAME=""
SELECTED_NPM_MIRROR_NAME=""
SELECTED_APT_MIRROR_NAME=""

CLAUDE_PACKAGE="@anthropic-ai/claude-code"
CLAUDE_MIN_VERSION="2.1.22"
CONFIG_DIR="$HOME/.claude"
CONFIG_FILE="$CONFIG_DIR/settings.json"
API_BASE_URL="https://open.bigmodel.cn/api/anthropic"
API_KEY_URL="https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys"
API_TIMEOUT_MS=3000000

# 全局变量存储安装的版本
INSTALLED_NODE_VERSION=""
INSTALLED_CLAUDE_PATH=""

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

log_warn() {
    echo "⚠️ $*"
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

# 检查是否有 sudo 权限
has_sudo() {
    if sudo -n true 2>/dev/null; then
        return 0  # 有 sudo 权限
    else
        return 1  # 无 sudo 权限
    fi
}

# 尝试执行 sudo 命令，如果失败则返回非零状态
try_sudo() {
    if has_sudo; then
        sudo "$@"
        return $?
    else
        log_warn "缺少 sudo 权限，跳过需要 root 权限的操作: $*"
        return 1
    fi
}

# ========================
#     镜像速度检测函数
# ========================

# 测试单个 URL 的响应时间（毫秒）
# 返回：响应时间（毫秒），失败返回 99999
test_url_speed() {
    local url="$1"
    local timeout="${2:-5}"  # 默认 5 秒超时

    # 使用 curl 测试连接时间，只测试 TCP 连接建立时间
    local result
    result=$(curl -s -o /dev/null -w "%{time_connect}" \
        --connect-timeout "$timeout" \
        --max-time "$((timeout * 2))" \
        "$url" 2>/dev/null) || result="99999"

    # 转换为毫秒（整数）
    if [[ "$result" == "99999" ]] || [ -z "$result" ]; then
        echo "99999"
    else
        # 将秒转换为毫秒并取整（使用 awk 代替 bc，因为 awk 更通用）
        echo "$result" | awk '{printf "%.0f", $1 * 1000}'
    fi
}

# 从镜像列表中选择最快的镜像
# 参数 1: 镜像数组名称
# 参数 2: 测试路径（可选）
# 输出：最快的镜像 URL|名称
select_fastest_mirror() {
    local mirror_array_name="$1"
    local test_path="${2:-/}"

    declare -n mirror_array="$mirror_array_name"
    local fastest_url=""
    local fastest_name=""
    local fastest_time=99999

    echo "   正在测试镜像源速度..."

    for mirror_entry in "${mirror_array[@]}"; do
        local url="${mirror_entry%%|*}"
        local name="${mirror_entry##*|}"
        local full_url="${url}${test_path}"

        # 测试速度
        local speed
        speed=$(test_url_speed "$full_url" 5)

        # 显示测试结果
        if [ "$speed" -lt 99999 ]; then
            printf "   %-15s: %d ms\n" "$name" "$speed"
            if [ "$speed" -lt "$fastest_time" ]; then
                fastest_time="$speed"
                fastest_url="$url"
                fastest_name="$name"
            fi
        else
            printf "   %-15s: 超时/失败\n" "$name"
        fi
    done

    echo "$fastest_url|$fastest_name"
}

# 检测并选择所有镜像源
detect_fastest_mirrors() {
    log_info "Detecting fastest mirror sources..."
    echo ""

    # 检测 NVM 镜像
    local nvm_result
    nvm_result=$(select_fastest_mirror "NVM_MIRRORS" "/install.sh")
    SELECTED_NVM_MIRROR="${nvm_result%%|*}"
    SELECTED_NVM_MIRROR_NAME="${nvm_result##*|}"
    echo "   ✅ 选中：$SELECTED_NVM_MIRROR_NAME"
    echo ""

    # 检测 Node.js 镜像
    local node_result
    node_result=$(select_fastest_mirror "NODE_MIRRORS" "/")
    SELECTED_NODE_MIRROR="${node_result%%|*}"
    SELECTED_NODE_MIRROR_NAME="${node_result##*|}"
    echo "   ✅ 选中：$SELECTED_NODE_MIRROR_NAME"
    echo ""

    # 检测 npm 镜像
    local npm_result
    npm_result=$(select_fastest_mirror "NPM_MIRRORS" "/")
    SELECTED_NPM_MIRROR="${npm_result%%|*}"
    SELECTED_NPM_MIRROR_NAME="${npm_result##*|}"
    echo "   ✅ 选中：$SELECTED_NPM_MIRROR_NAME"
    echo ""

    # 检测 apt 镜像
    local apt_result
    apt_result=$(select_fastest_mirror "APT_MIRRORS" "/")
    SELECTED_APT_MIRROR="${apt_result%%|*}"
    SELECTED_APT_MIRROR_NAME="${apt_result##*|}"
    echo "   ✅ 选中：$SELECTED_APT_MIRROR_NAME"
    echo ""

    log_success "Mirror detection completed"
    echo ""
}

# ========================
#     Node.js 安装函数
# ========================

install_nodejs() {
    local platform=$(uname -s)

    case "$platform" in
        Linux|Darwin)
            log_info "Installing Node.js on $platform..."

            # 设置 Node.js 镜像源（用于 nvm 下载 Node.js）
            export NVM_NODEJS_ORG_MIRROR="$SELECTED_NODE_MIRROR"

            # 检查 nvm 是否已安装
            if [ -s "$HOME/.nvm/nvm.sh" ]; then
                log_success "nvm is already installed"
            else
                # 安装 nvm（使用速度检测选中的镜像）
                log_info "Installing nvm ($NVM_VERSION) from $SELECTED_NVM_MIRROR_NAME..."
                if ! curl -s "$SELECTED_NVM_MIRROR/install.sh" | bash; then
                    log_info "Mirror failed, trying alternative..."
                    # 尝试备用镜像
                    for mirror_entry in "${NVM_MIRRORS[@]}"; do
                        local url="${mirror_entry%%|*}"
                        local name="${mirror_entry##*|}"
                        if [ "$url" != "$SELECTED_NVM_MIRROR" ]; then
                            log_info "Trying $name..."
                            if curl -s "$url/install.sh" | bash; then
                                SELECTED_NVM_MIRROR="$url"
                                SELECTED_NVM_MIRROR_NAME="$name"
                                break
                            fi
                        fi
                    done
                fi
                log_success "nvm installed from: $SELECTED_NVM_MIRROR_NAME"
            fi

            # 加载 nvm
            log_info "Loading nvm environment..."
            \. "$HOME/.nvm/nvm.sh"

            # 安装 Node.js（使用镜像源）
            log_info "Installing Node.js $NODE_INSTALL_VERSION from $SELECTED_NODE_MIRROR_NAME..."
            nvm install "$NODE_INSTALL_VERSION"

            # 切换到新安装的 Node.js 版本
            log_info "Switching to Node.js $NODE_INSTALL_VERSION..."
            nvm use "$NODE_INSTALL_VERSION"

            # 获取实际安装的精确版本号
            INSTALLED_NODE_VERSION=$(node -v | sed 's/v//')

            # 设置为默认版本（使用精确版本号）
            log_info "Setting Node.js v$INSTALLED_NODE_VERSION as default..."
            nvm alias default "$INSTALLED_NODE_VERSION"

            # 验证安装
            node -v &>/dev/null || {
                log_error "Node.js installation failed"
                exit 1
            }
            log_success "Node.js installed: $(node -v)"
            log_success "npm version: $(npm -v)"

            # 安装/升级 pnpm 到最新版本（使用选中的镜像）
            log_info "Installing/upgrading pnpm to latest version..."
            npm install -g pnpm@latest --registry="$SELECTED_NPM_MIRROR" || {
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
    # 首先加载 nvm 环境（如果存在）
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        \. "$HOME/.nvm/nvm.sh"
    fi

    if command -v node &>/dev/null; then
        current_version=$(node -v | sed 's/v//')
        major_version=$(echo "$current_version" | cut -d. -f1)

        if [ "$major_version" -ge "$NODE_MIN_VERSION" ]; then
            INSTALLED_NODE_VERSION="$current_version"
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

# 获取 Claude Code 最新版本
get_latest_claude_version() {
    local npm_registry="$1"
    local latest_version
    latest_version=$(npm view "$CLAUDE_PACKAGE" version --registry="$npm_registry" 2>/dev/null || echo "")
    if [ -z "$latest_version" ]; then
        echo ""
    else
        echo "$latest_version"
    fi
}

# 安装指定版本的 Claude Code
install_claude_code_version() {
    local version="$1"
    local npm_registry="$2"

    log_info "Installing Claude Code $version..."
    npm install -g "$CLAUDE_PACKAGE@$version" --registry="$npm_registry" || {
        log_error "Failed to install claude-code $version"
        return 1
    }
    INSTALLED_CLAUDE_PATH=$(which claude 2>/dev/null || echo "")
    log_success "Claude Code installed successfully: $(claude --version)"
    return 0
}

install_claude_code() {
    # 首先加载 nvm 环境（如果存在）
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        \. "$HOME/.nvm/nvm.sh"
    fi

    # 使用选中的 npm 镜像源
    local npm_registry="$SELECTED_NPM_MIRROR"

    if command -v claude &>/dev/null; then
        current_version=$(claude --version 2>/dev/null || echo "unknown")
        log_info "Claude Code is already installed: $current_version"

        # 获取 claude 命令路径
        INSTALLED_CLAUDE_PATH=$(which claude 2>/dev/null || echo "")

        # 检查版本
        if version_compare "$current_version" "$CLAUDE_MIN_VERSION"; then
            log_success "Claude Code version $current_version meets requirement (>= $CLAUDE_MIN_VERSION)"
        else
            log_info "Claude Code version $current_version is outdated. Upgrading to $CLAUDE_MIN_VERSION..."
            npm install -g "$CLAUDE_PACKAGE@$CLAUDE_MIN_VERSION" --registry="$npm_registry" || {
                log_error "Failed to upgrade claude-code"
                exit 1
            }
            new_version=$(claude --version 2>/dev/null || echo "unknown")
            INSTALLED_CLAUDE_PATH=$(which claude 2>/dev/null || echo "")
            log_success "Claude Code upgraded to: $new_version"
        fi
    else
        log_info "Claude Code 未安装"
        echo ""

        # 获取最新版本
        local latest_version
        latest_version=$(get_latest_claude_version "$npm_registry")

        if [ -z "$latest_version" ]; then
            log_warn "无法获取最新版本信息，将安装默认版本: $CLAUDE_MIN_VERSION"
            install_claude_code_version "$CLAUDE_MIN_VERSION" "$npm_registry"
            return $?
        fi

        # 显示版本选择菜单
        echo "📦 请选择要安装的 Claude Code 版本:"
        echo ""
        echo "   1) 最新版本: $latest_version"
        echo "   2) 默认版本: $CLAUDE_MIN_VERSION"
        echo "   3) 指定版本"
        echo ""
        read -p "   请输入选项 [1-3]: " version_choice

        case "$version_choice" in
            1)
                echo ""
                log_info "正在安装最新版本: $latest_version"
                install_claude_code_version "$latest_version" "$npm_registry"
                ;;
            2)
                echo ""
                log_info "正在安装默认版本: $CLAUDE_MIN_VERSION"
                install_claude_code_version "$CLAUDE_MIN_VERSION" "$npm_registry"
                ;;
            3)
                echo ""
                read -p "   请输入版本号 (例如: 2.1.30): " custom_version
                if [ -z "$custom_version" ]; then
                    log_error "版本号不能为空"
                    install_claude_code_version "$CLAUDE_MIN_VERSION" "$npm_registry"
                else
                    log_info "正在安装指定版本: $custom_version"
                    install_claude_code_version "$custom_version" "$npm_registry"
                fi
                ;;
            *)
                echo ""
                log_warn "无效选项，将安装默认版本: $CLAUDE_MIN_VERSION"
                install_claude_code_version "$CLAUDE_MIN_VERSION" "$npm_registry"
                ;;
        esac
    fi
}

# ========================
#     Happy 安装
# ========================

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

# 配置国内 apt 镜像源
configure_apt_mirror() {
    if [ -f /etc/debian_version ]; then
        # 检查是否有 sudo 权限
        if ! has_sudo; then
            log_warn "缺少 sudo 权限，跳过 apt 镜像配置（将使用系统默认源）"
            return 0
        fi

        # 检测是否为 Raspberry Pi OS
        local is_rpi=false
        if [ -f /etc/rpi-issue ] || grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
            is_rpi=true
        fi

        # 如果已配置镜像源，则跳过
        local configured_mirror=""
        for mirror_entry in "${APT_MIRRORS[@]}"; do
            local url="${mirror_entry%%|*}"
            local domain="${url#https://}"
            domain="${domain%%/*}"
            if grep -q "$domain" /etc/apt/sources.list 2>/dev/null; then
                configured_mirror="$domain"
                break
            fi
        done

        if [ -n "$configured_mirror" ]; then
            log_info "Apt mirror already configured: $configured_mirror"
            return 0
        fi

        log_info "Configuring apt mirror from fastest source: $SELECTED_APT_MIRROR_NAME..."

        # 备份原始源
        sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true

        # 提取镜像域名
        local mirror_domain="${SELECTED_APT_MIRROR#https://}"
        mirror_domain="${mirror_domain%%/*}"

        if [ "$is_rpi" = true ]; then
            # Raspberry Pi OS 使用不同的源
            log_info "Detected Raspberry Pi OS, configuring RPi mirrors..."
            sudo tee /etc/apt/sources.list > /dev/null << EOF
deb https://$mirror_domain/raspbian/raspbian/ bookworm main contrib non-free non-free-firmware
deb https://$mirror_domain/raspbian/raspbian/ bookworm-updates main contrib non-free non-free-firmware
deb https://$mirror_domain/raspbian/raspbian/ bookworm-backports main contrib non-free non-free-firmware
deb https://$mirror_domain/raspberrypi/ bookworm main
EOF
            log_success "apt mirror configured: $SELECTED_APT_MIRROR_NAME RPi mirror"
        else
            # 检测 Debian 版本
            local debian_version=$(cat /etc/debian_version | cut -d. -f1)
            local codename=""

            case "$debian_version" in
                12) codename="bookworm" ;;
                11) codename="bullseye" ;;
                10) codename="buster" ;;
                *)
                    log_info "Unknown Debian version, using official source"
                    return 0
                    ;;
            esac

            # 使用选中的镜像源
            sudo tee /etc/apt/sources.list > /dev/null << EOF
deb https://$mirror_domain/debian/ ${codename} main contrib non-free non-free-firmware
deb https://$mirror_domain/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb https://$mirror_domain/debian/ ${codename}-backports main contrib non-free non-free-firmware
deb https://$mirror_domain/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF
            log_success "apt mirror configured: $SELECTED_APT_MIRROR_NAME"
        fi
    fi
}

install_jq() {
    if command -v jq &>/dev/null; then
        log_success "jq is already installed: $(jq --version)"
        return 0
    fi

    local platform=$(uname -s)

    case "$platform" in
        Linux)
            log_info "Installing jq on Linux..."

            # 检查是否有 sudo 权限
            if ! has_sudo; then
                log_warn "缺少 sudo 权限，无法安装 jq"
                log_warn "请手动安装 jq: sudo apt-get install -y jq"
                return 0
            fi

            # 检测 Linux 发行版
            if [ -f /etc/debian_version ]; then
                # Debian/Ubuntu - 先配置国内镜像
                configure_apt_mirror
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
                log_warn "Unsupported Linux distribution. Please install jq manually."
                return 0
            fi
            ;;
        Darwin)
            log_info "Installing jq on macOS..."

            # 检查是否安装了 Homebrew
            if command -v brew &>/dev/null; then
                brew install jq
            else
                log_warn "Homebrew not found. Please install Homebrew first: https://brew.sh"
                return 0
            fi
            ;;
        *)
            log_warn "Unsupported platform: $platform"
            return 0
            ;;
    esac

    # 验证安装
    if command -v jq &>/dev/null; then
        log_success "jq installed successfully: $(jq --version)"
    else
        log_warn "jq installation failed, but continuing..."
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

            # 检查是否有 sudo 权限
            if ! has_sudo; then
                log_warn "缺少 sudo 权限，无法安装 tmux"
                log_warn "请手动安装 tmux: sudo apt-get install -y tmux"
                return 0
            fi

            # 检测 Linux 发行版
            if [ -f /etc/debian_version ]; then
                # Debian/Ubuntu - 先配置国内镜像
                configure_apt_mirror
                sudo apt-get update && sudo apt-get install -y tmux
            elif [ -f /etc/redhat-release ]; then
                # RHEL/CentOS/Fedora
                sudo yum install -y tmux || sudo dnf install -y tmux
            elif [ -f /etc/arch-release ]; then
                # Arch Linux
                sudo pacman -S --noconfirm tmux
            else
                log_warn "Unsupported Linux distribution. Please install tmux manually."
                return 0
            fi
            ;;
        Darwin)
            log_info "Installing tmux on macOS..."

            # 检查是否安装了 Homebrew
            if command -v brew &>/dev/null; then
                brew install tmux
            else
                log_warn "Homebrew not found. Please install Homebrew first: https://brew.sh"
                return 0
            fi
            ;;
        *)
            log_warn "Unsupported platform: $platform"
            return 0
            ;;
    esac

    # 验证安装
    if command -v tmux &>/dev/null; then
        log_success "tmux installed successfully: $(tmux -V)"
    else
        log_warn "tmux installation failed, but continuing..."
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

            # 检查是否有 sudo 权限
            if ! has_sudo; then
                log_warn "缺少 sudo 权限，无法安装 Git"
                log_warn "请手动安装 Git: sudo apt-get install -y git"
                return 0
            fi

            # 检测 Linux 发行版
            if [ -f /etc/debian_version ]; then
                # Debian/Ubuntu - 先配置国内镜像
                configure_apt_mirror
                sudo apt-get update && sudo apt-get install -y git
            elif [ -f /etc/redhat-release ]; then
                # RHEL/CentOS/Fedora
                sudo yum install -y git || sudo dnf install -y git
            elif [ -f /etc/arch-release ]; then
                # Arch Linux
                sudo pacman -S --noconfirm git
            else
                log_warn "Unsupported Linux distribution. Please install Git manually."
                return 0
            fi
            ;;
        Darwin)
            log_info "Installing Git on macOS..."

            # 检查是否安装了 Homebrew
            if command -v brew &>/dev/null; then
                brew install git
            else
                # macOS 通常自带 Git，如果不存在则提示用户安装
                log_warn "Git not found. Please install Git via: xcode-select --install"
                return 0
            fi
            ;;
        *)
            log_warn "Unsupported platform: $platform"
            return 0
            ;;
    esac

    # 验证安装
    if command -v git &>/dev/null; then
        log_success "Git installed successfully: $(git --version)"
    else
        log_warn "Git installation failed, but continuing..."
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
                # 检查是否有 sudo 权限
                if ! has_sudo; then
                    log_warn "缺少 sudo 权限，跳过中文 locale 安装"
                    # 检查是否已有中文 locale 支持
                    if locale -a 2>/dev/null | grep -q "zh_CN.utf8"; then
                        log_success "系统已支持中文 locale"
                    else
                        log_warn "系统不支持中文 locale，可能影响中文显示"
                    fi
                    return 0
                fi

                # Debian/Ubuntu - 先配置国内镜像
                configure_apt_mirror
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
#   PATH 优先级配置函数
# ========================

configure_path_priority() {
    log_info "Configuring PATH priority..."

    # 加载 nvm 环境以获取正确的路径
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        \. "$HOME/.nvm/nvm.sh"
    fi

    # 确定 Node.js 路径
    local node_path=""
    if [ -n "$INSTALLED_NODE_VERSION" ] && [ -d "$HOME/.nvm/versions/node/v$INSTALLED_NODE_VERSION/bin" ]; then
        node_path="$HOME/.nvm/versions/node/v$INSTALLED_NODE_VERSION/bin"
    elif [ -d "$HOME/.nvm/versions/node/v22.22.0/bin" ]; then
        # 回退到常见版本
        node_path="$HOME/.nvm/versions/node/v22.22.0/bin"
        INSTALLED_NODE_VERSION="22.22.0"
    fi

    # 确定 Claude Code 路径
    local claude_path=""
    if [ -n "$INSTALLED_CLAUDE_PATH" ]; then
        # 获取 claude 所在目录
        claude_path=$(dirname "$INSTALLED_CLAUDE_PATH")
    elif command -v claude &>/dev/null; then
        claude_path=$(dirname "$(which claude)")
    fi

    # 创建 PATH 配置内容
    local path_config=""
    if [ -n "$node_path" ]; then
        path_config="$path_config
# Prioritize Node.js v$INSTALLED_NODE_VERSION
if [ -d \"$node_path\" ] ; then
    PATH=\"$node_path:\$PATH\"
fi"
    fi

    if [ -n "$claude_path" ]; then
        path_config="$path_config

# Prioritize Claude Code
if [ -d \"$claude_path\" ] ; then
    PATH=\"$claude_path:\$PATH\"
fi"
    fi

    if [ -z "$path_config" ]; then
        log_info "No PATH configuration needed (paths not found)"
        return 0
    fi

    # 检查 ~/.profile 是否存在
    local profile_file="$HOME/.profile"
    if [ ! -f "$profile_file" ]; then
        touch "$profile_file"
    fi

    # 检查配置是否已存在
    if grep -q "Prioritize Node.js" "$profile_file" 2>/dev/null; then
        log_success "PATH priority configuration already exists in ~/.profile"
    else
        # 追加到 ~/.profile 开头（在任何现有内容之前）
        local temp_file
        temp_file=$(mktemp)
        echo "$path_config" > "$temp_file"
        cat "$profile_file" >> "$temp_file"
        mv "$temp_file" "$profile_file"
        log_success "PATH priority added to ~/.profile"
    fi

    # 同时更新当前 shell 的 PATH
    if [ -n "$node_path" ]; then
        export PATH="$node_path:$PATH"
    fi
    if [ -n "$claude_path" ]; then
        export PATH="$claude_path:$PATH"
    fi

    # 验证优先级
    log_info "Verifying PATH priority..."
    if command -v node &>/dev/null; then
        log_info "Node.js path: $(which node)"
    fi
    if command -v claude &>/dev/null; then
        log_info "Claude Code path: $(which claude)"
    fi

    log_success "PATH priority configured successfully"
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
    echo ""

    # 检测系统信息
    local platform=$(uname -s)
    local arch=$(uname -m)
    echo "📋 System Information:"
    echo "   Platform: $platform"
    echo "   Architecture: $arch"

    # 检测是否为 Raspberry Pi
    if [ -f /etc/rpi-issue ] || grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        echo "   Device: Raspberry Pi detected"
        log_info "Raspberry Pi optimization enabled"
    fi
    echo ""

    # 检测并选择最快的镜像源
    detect_fastest_mirrors

    check_nodejs
    install_claude_code
    configure_path_priority
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
