#!/usr/bin/env bash
#
# setup_server.sh — 新 Ubuntu 服务器一键环境配置
#
# 安装内容：
#   1. claude  (Claude Code CLI)
#   2. codex   (OpenAI Codex CLI)
#   3. oh-my-zsh + 插件 (zsh-autosuggestions, zsh-syntax-highlighting)
#   4. miniconda3
#
# 全部非交互式安装，可重复执行（幂等）。
#
# 用法:  bash setup_server.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------
log()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m[!] %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 0. 基础依赖 (curl / wget / git / zsh)
# ---------------------------------------------------------------------------
log "安装基础依赖 (curl wget git zsh)"
if command -v apt-get >/dev/null 2>&1; then
    SUDO=""
    [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    $SUDO apt-get update -y
    $SUDO apt-get install -y curl wget git zsh ca-certificates
else
    warn "未检测到 apt-get，请确认 curl/wget/git/zsh 已安装"
fi

# ---------------------------------------------------------------------------
# 1. Claude Code CLI
# ---------------------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
    log "claude 已安装，跳过"
else
    log "安装 claude"
    curl -fsSL https://claude.ai/install.sh | bash
fi

# ---------------------------------------------------------------------------
# 2. Codex CLI
# ---------------------------------------------------------------------------
if command -v codex >/dev/null 2>&1; then
    log "codex 已安装，跳过"
else
    log "安装 codex"
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
fi

# ---------------------------------------------------------------------------
# 3. oh-my-zsh (非交互式，不自动切换 shell / 不启动 zsh)
# ---------------------------------------------------------------------------
if [ -d "$HOME/.oh-my-zsh" ]; then
    log "oh-my-zsh 已安装，跳过"
else
    log "安装 oh-my-zsh"
    # RUNZSH=no  安装后不立即进入 zsh（否则脚本会在此处阻塞/中断）
    # CHSH=no    先不改默认 shell，稍后统一处理
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# ---------------------------------------------------------------------------
# 3b. zsh 插件
# ---------------------------------------------------------------------------
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

clone_plugin() {
    local repo="$1" dest="$2"
    if [ -d "$dest" ]; then
        log "插件已存在: $(basename "$dest")，跳过"
    else
        log "克隆插件: $(basename "$dest")"
        git clone --depth=1 "$repo" "$dest"
    fi
}

clone_plugin https://github.com/zsh-users/zsh-autosuggestions \
             "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting.git \
             "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# ---------------------------------------------------------------------------
# 3c. 在 .zshrc 中启用插件
# ---------------------------------------------------------------------------
ZSHRC="$HOME/.zshrc"
DESIRED_PLUGINS="git zsh-autosuggestions zsh-syntax-highlighting"

log "配置 .zshrc 插件列表"
if [ -f "$ZSHRC" ] && grep -qE '^\s*plugins=\(' "$ZSHRC"; then
    # 替换已有的 plugins=(...) 行
    sed -i "s/^\s*plugins=(.*)/plugins=($DESIRED_PLUGINS)/" "$ZSHRC"
else
    printf '\nplugins=(%s)\n' "$DESIRED_PLUGINS" >> "$ZSHRC"
fi

# ---------------------------------------------------------------------------
# 4. Miniconda3
# ---------------------------------------------------------------------------
MINICONDA_DIR="$HOME/miniconda3"
if [ -d "$MINICONDA_DIR" ]; then
    log "miniconda 已安装 ($MINICONDA_DIR)，跳过"
else
    log "下载并安装 miniconda3"
    TMP_INSTALLER="$HOME/Miniconda3-latest-Linux-x86_64.sh"
    [ -f "$TMP_INSTALLER" ] || \
        wget -O "$TMP_INSTALLER" https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    # -b 批处理(默认)  -p 安装路径
    bash "$TMP_INSTALLER" -b -p "$MINICONDA_DIR"
fi

# 初始化 conda 到 zsh（写入 .zshrc 的 conda init 块）
log "初始化 conda for zsh"
"$MINICONDA_DIR/bin/conda" init zsh || warn "conda init zsh 失败，可稍后手动执行"

# ---------------------------------------------------------------------------
# 5. 将默认 shell 切换为 zsh
# ---------------------------------------------------------------------------
# 优先用 chsh 改默认 shell；域账户 / LDAP 用户 chsh 通常会失败，
# 因此再加一个兜底：在 .bashrc 里让交互式 bash 自动切到 zsh。
if [ "${SHELL:-}" != "$(command -v zsh)" ]; then
    log "尝试将默认 shell 切换为 zsh"
    if chsh -s "$(command -v zsh)" 2>/dev/null; then
        log "默认 shell 已切换为 zsh（重新登录后生效）"
    else
        warn "chsh 失败（常见于域/LDAP 账户），改用 .bashrc 兜底"
    fi
fi

# 兜底：交互式 bash 登录时自动切换到 zsh（非交互 shell 不受影响，
# 避免破坏 scp / rsync / ssh host cmd 等）
if [ -f "$HOME/.bashrc" ] && grep -q 'exec zsh' "$HOME/.bashrc"; then
    log ".bashrc 已配置自动切换 zsh，跳过"
else
    log "在 .bashrc 中配置交互式自动切换 zsh"
    cat >> "$HOME/.bashrc" <<'EOF'

# 交互式 bash 登录时自动切换到 zsh（非交互 shell 不受影响）
if [ -z "$ZSH_VERSION" ] && [[ $- == *i* ]] && command -v zsh >/dev/null 2>&1; then
    exec zsh
fi
EOF
fi

# ---------------------------------------------------------------------------
# 完成
# ---------------------------------------------------------------------------
log "全部完成！"
cat <<'EOF'

后续操作:
  1. 重新登录，或执行:  exec zsh
  2. 验证:
       claude --version
       codex --version
       conda --version
  3. 若 claude/codex 命令找不到, 确认 ~/.local/bin 在 PATH 中:
       export PATH="$HOME/.local/bin:$PATH"

EOF
