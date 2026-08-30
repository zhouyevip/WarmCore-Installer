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
