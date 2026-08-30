# WarmCore 私有服务器安装包

本仓库只包含安装编排文件，不包含 WarmCore 源码。

首次开放安装前，请确认 GHCR 中的 `warmcore-server` 和 `warmcore-digital-human` 镜像已设为 Public；否则用户需要先执行 `docker login ghcr.io`。

## 安装

### Windows + Docker Desktop

在 PowerShell 执行：

```powershell
irm https://raw.githubusercontent.com/zhouyevip/WarmCore-Installer/main/install.ps1 | iex
```

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/zhouyevip/WarmCore-Installer/main/install.sh -o install.sh
bash install.sh
```

安装完成后打开 `http://localhost:8080/`。手机扫码时使用电脑的局域网地址。

从旧版源码部署迁移时，安装器固定使用 Compose 项目名 `warmcore`，会复用原有数据卷；只删除旧容器，不删除数据卷。

基础版只启动 Agent 和关系人。其他模块按需安装：

```powershell
# 相册
docker compose -f docker-compose.release.yml --profile album up -d
# 数字人
docker compose -f docker-compose.release.yml --profile digital-human up -d
```
