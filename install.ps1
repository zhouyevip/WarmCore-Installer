$ErrorActionPreference = 'Stop'

$rawBase = if ($env:DOWNLOAD_BASE) { $env:DOWNLOAD_BASE } else { 'https://raw.githubusercontent.com/zhouyevip/WarmCore-Installer/main' }
$compose = Join-Path (Get-Location) 'docker-compose.release.yml'
$caddy = Join-Path (Get-Location) 'Caddyfile.private'
$envFile = Join-Path (Get-Location) '.env'

function Write-Step([string]$Message) { Write-Host "[WarmCore] $Message" -ForegroundColor Yellow }
function New-Secret {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw '未找到 Docker，请先安装 Docker Desktop' }
docker compose version *> $null
if ($LASTEXITCODE -ne 0) { throw '未找到 Docker Compose v2，请升级 Docker Desktop' }

Write-Step '下载安装编排文件'
Invoke-WebRequest "$rawBase/docker-compose.release.yml" -OutFile $compose -UseBasicParsing
Invoke-WebRequest "$rawBase/Caddyfile.private" -OutFile $caddy -UseBasicParsing

if (-not (Test-Path $envFile)) {
  $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1 -ExpandProperty IPAddress)
  if (-not $lanIp) { $lanIp = '127.0.0.1' }
  $jwt = if ($env:HUB_JWT_SECRET) { $env:HUB_JWT_SECRET } else { New-Secret }
  $minioSecret = if ($env:MINIO_SECRET_KEY) { $env:MINIO_SECRET_KEY } else { New-Secret }
  $watchToken = if ($env:WATCHTOWER_API_TOKEN) { $env:WATCHTOWER_API_TOKEN } else { New-Secret }
  @"
WARMCORE_VERSION=latest
COMPOSE_PROJECT_NAME=warmcore
HUB_JWT_SECRET=$jwt
CLOUD_URL=
OLLAMA_BASE_URL=http://host.docker.internal:11434
DIGITAL_HUMAN_ADVERTISE_HOST=$lanIp
MINIO_ACCESS_KEY=warmcore
MINIO_SECRET_KEY=$minioSecret
WATCHTOWER_API_TOKEN=$watchToken
DOCKER_CONFIG_JSON=$env:USERPROFILE\.docker\config.json
"@ | Set-Content -LiteralPath $envFile -Encoding UTF8
  Write-Step '已生成本地配置文件 .env'
}

New-Item -ItemType Directory -Force -Path @(
  'data/digital-human/certs', 'data/digital-human/avatars', 'data/digital-human/uploads',
  'data/digital-human/templates', 'data/digital-human/liveportrait', 'data/digital-human/models',
  'data/digital-human/ref', 'data/digital-human/hf-cache', 'data/digital-human/torch-cache',
  'data/digital-human/lt_patched'
) | Out-Null

Write-Step '启动 WarmCore 基础服务'
docker compose -f $compose up -d
if ($LASTEXITCODE -ne 0) { throw '启动失败，请执行 docker compose -f docker-compose.release.yml logs' }
Write-Host "完成：打开 http://localhost:8080/" -ForegroundColor Green
Write-Host '局域网手机访问请使用 .env 中 DIGITAL_HUMAN_ADVERTISE_HOST 对应的地址。'
