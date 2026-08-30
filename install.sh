#!/usr/bin/env bash
# WarmCore 私人服务器 · 一键安装脚本（镜像版）
#
# 用法（Linux / macOS / Git Bash）——先下载到本地，再执行（不推荐管道直接执行远程脚本）：
#   curl -fsSL https://raw.githubusercontent.com/zhouyevip/WarmCore-Installer/main/install.sh -o install.sh
#   bash install.sh
#
# 行为：
#   1. 检查 docker / docker compose
#   2. 下载官方 docker-compose.release.yml 与 Caddyfile.private（可用 DOWNLOAD_BASE 换镜像加速）
#   3. 交互收集配置写入 .env（HUB_JWT_SECRET 自动生成 64 位随机密钥）
#   4. 生成数字人调试用自签证书（Caddy 443 块依赖）
#   5. docker compose 拉镜像启动，打印访问地址与更新命令
#
# 环境变量（可免交互，或测试用）：
#   NONINTERACTIVE=1   全部用默认值/已设环境变量，不再询问
#   SKIP_DOWNLOAD=1    跳过下载（本地已有 docker-compose.release.yml / Caddyfile.private，开发调试用）
#   DOWNLOAD_BASE      下载基址（默认 GitHub raw；国内可换加速前缀）
set -euo pipefail

REPO_RAW="${DOWNLOAD_BASE:-https://raw.githubusercontent.com/zhouyevip/WarmCore-Installer/main}"
COMPOSE_FILE="docker-compose.release.yml"
CADDY_FILE="Caddyfile.private"

say() { printf '\n\033[1;33m[WarmCore]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[安装失败]\033[0m %s\n' "$*" >&2; exit 1; }

# ── 1. 前置检查 ───────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || die "未找到 docker，请先安装 Docker（https://docs.docker.com/engine/install/）"
docker compose version >/dev/null 2>&1 || die "未找到 docker compose v2，请升级 Docker 或安装 compose 插件"

# ── 2. 下载官方编排文件 ───────────────────────────────────────
fetch() { # fetch <远程文件> <本地文件>
  if [ "${SKIP_DOWNLOAD:-0}" = "1" ]; then
    [ -f "$2" ] || die "SKIP_DOWNLOAD=1 但本地缺少 $2"
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_RAW/$1" -o "$2" || die "下载 $1 失败（网络不通可设 DOWNLOAD_BASE 换加速源）"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$REPO_RAW/$1" || die "下载 $1 失败（网络不通可设 DOWNLOAD_BASE 换加速源）"
  else
    die "需要 curl 或 wget 用于下载编排文件"
  fi
}
say "下载官方编排文件（源：$REPO_RAW）"
fetch "$COMPOSE_FILE" "$COMPOSE_FILE"
fetch "$CADDY_FILE" "$CADDY_FILE"

# ── 3. 生成 .env ──────────────────────────────────────────────
if [ -f .env ]; then
  say "已存在 .env，保留现有配置（如需重装请先备份删除 .env）"
else
  # 随机密钥：优先 openssl，退化到 /dev/urandom（≥32 字节）
  gen_secret() {
    if command -v openssl >/dev/null 2>&1; then openssl rand -hex 32; else head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; fi
  }
  HUB_JWT_SECRET="${HUB_JWT_SECRET:-$(gen_secret)}"
  [ "${#HUB_JWT_SECRET}" -ge 32 ] || die "HUB_JWT_SECRET 需 ≥32 位"

  # 自动探测宿主机局域网 IP（部署门户二维码/数字人广播地址用）
  detect_lan_ip() {
    if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
      hostname -I | awk '{print $1}'; return
    fi
    if command -v ipconfig >/dev/null 2>&1; then
      ipconfig 2>/dev/null | grep -o '192\.168\.[0-9.]*\|10\.[0-9.]*\|172\.\(1[6-9]\|2[0-9]\|3[01]\)\.[0-9.]*' | head -1; return
    fi
    echo ""
  }
  DEFAULT_LAN_IP="$(detect_lan_ip)"
  DEFAULT_LAN_IP="${DEFAULT_LAN_IP:-127.0.0.1}"

  ask() { # ask <提示> <默认值> <变量名>
    local v=""
    if [ "${NONINTERACTIVE:-0}" = "1" ] || [ ! -t 0 ]; then
      v="${!3:-}"
    else
      read -r -p "$1 [$2]: " v </dev/tty || v=""
      [ -z "$v" ] && v="$2"
    fi
    [ -z "$v" ] && v="$2"
    printf '%s' "$v"
  }

  CLOUD_URL="$(ask '云端总管地址（留空=纯本地运行）' '' CLOUD_URL)"
  OLLAMA_BASE_URL="$(ask 'ollama 地址（模型自备，不随镜像分发）' 'http://host.docker.internal:11434' OLLAMA_BASE_URL)"
  DIGITAL_HUMAN_ADVERTISE_HOST="$(ask '宿主机局域网 IP（手机访问用）' "$DEFAULT_LAN_IP" DIGITAL_HUMAN_ADVERTISE_HOST)"
  MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-warmcore}"
  MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-$(gen_secret)}"
  WATCHTOWER_API_TOKEN="${WATCHTOWER_API_TOKEN:-$(gen_secret)}"

  cat > .env <<EOF
# WarmCore 私有部署配置（由 install.sh 生成；密钥请勿外传）
WARMCORE_VERSION=latest
COMPOSE_PROJECT_NAME=warmcore
# WARMCORE_REGISTRY=ghcr.io/zhouyevip   # 国内拉取慢时切换镜像源
HUB_JWT_SECRET=$HUB_JWT_SECRET
CLOUD_URL=$CLOUD_URL
OLLAMA_BASE_URL=$OLLAMA_BASE_URL
DIGITAL_HUMAN_ADVERTISE_HOST=$DIGITAL_HUMAN_ADVERTISE_HOST
MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY
MINIO_SECRET_KEY=$MINIO_SECRET_KEY
# 一键更新：watchtower 令牌 + 宿主机 docker 登录凭据路径（私有镜像拉取）
WATCHTOWER_API_TOKEN=$WATCHTOWER_API_TOKEN
DOCKER_CONFIG_JSON=$HOME/.docker/config.json
EOF
  chmod 600 .env 2>/dev/null || true
  say "已生成 .env（HUB_JWT_SECRET 随机 64 位）"
fi

# ── 4. 目录与自签证书（Caddyfile 443 块依赖证书文件存在）──────
mkdir -p data/digital-human/certs data/digital-human/avatars data/digital-human/uploads \
         data/digital-human/templates data/digital-human/liveportrait \
         data/digital-human/models data/digital-human/ref data/digital-human/hf-cache \
         data/digital-human/torch-cache data/digital-human/lt_patched
# watchtower 私有镜像拉取需要宿主机的 docker 登录凭据文件
[ -f "$HOME/.docker/config.json" ] || { mkdir -p "$HOME/.docker" && echo '{}' > "$HOME/.docker/config.json"; }
if command -v openssl >/dev/null 2>&1 && [ ! -f data/digital-human/certs/dh-cert.pem ]; then
  ADVERTISE_HOST="$(grep -E '^DIGITAL_HUMAN_ADVERTISE_HOST=' .env | cut -d= -f2-)"
  ADVERTISE_HOST="${ADVERTISE_HOST:-127.0.0.1}"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout data/digital-human/certs/dh-key.pem \
    -out data/digital-human/certs/dh-cert.pem -days 3650 -subj "/CN=${ADVERTISE_HOST}" >/dev/null 2>&1 \
    && say "已生成数字人调试用自签证书（浏览器首次访问 https 需手动信任）" || true
fi

# ── 5. 拉镜像启动 ─────────────────────────────────────────────
say "拉取镜像并启动（首次约 1~3 分钟）"
docker compose -f "$COMPOSE_FILE" up -d || die "启动失败，请执行 docker compose -f $COMPOSE_FILE logs 查看日志"

LAN_IP="$(grep -E '^DIGITAL_HUMAN_ADVERTISE_HOST=' .env | cut -d= -f2-)"
LAN_IP="${LAN_IP:-127.0.0.1}"

cat <<EOF

════════════════════════════════════════════════════════
  WarmCore 私人服务器已启动
────────────────────────────────────────────────────────
  部署门户   http://${LAN_IP}:8080/
  家庭后台   http://${LAN_IP}:8080/admin
  检查更新   http://${LAN_IP}:8080/admin/update（家庭后台内）

  更新到最新版：
    docker compose -f ${COMPOSE_FILE} pull && docker compose -f ${COMPOSE_FILE} up -d

  启用数字人生成服务（GPU）：
    docker compose -f ${COMPOSE_FILE} --profile digital-human up -d

  拉取 ollama 模型（模型不随镜像分发，自备 ollama 后执行）：
    docker exec -it <ollama容器> ollama pull qwen3:8b
════════════════════════════════════════════════════════
EOF
