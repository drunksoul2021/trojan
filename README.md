# Trojan：Debian 13 x64 独立安装版

本仓库包含管理程序、管理网页、Trojan 内核源码、ACME 客户端、安装脚本和构建发布流程。安装与更新只下载 **drunksoul2021/trojan** 的发布包，不依赖其他管理项目的发布包或镜像。

## 一键安装

准备一台 **Debian 13 (trixie) x64** 服务器，以及一个只通过 **A 记录** 指向服务器公网 IPv4 的域名。该域名不要配置 AAAA 记录。云厂商防火墙需放行 **443/TCP**，SSH 端口保持原配置。

登录服务器，以 root 执行：

```bash
curl -4 -fsSL --retry 3 https://raw.githubusercontent.com/drunksoul2021/trojan/master/install.sh -o /tmp/trojan-install.sh && bash /tmp/trojan-install.sh
```

按照提示输入域名和至少 12 位管理员密码。脚本自动完成：

- 备份并修复 Debian APT 主源、更新源、安全源和 Signed-By 配置，保留第三方源。
- APT 和安装下载使用 IPv4；保留系统 DNS 配置。
- 使用 `apt-get install -y docker.io` 安装 Docker，设置开机启动。
- 新装数据库使用官方 `mariadb:11.4` 镜像，端口仅绑定 `127.0.0.1:3307`。
- 安装本仓库构建的管理程序及内核，管理网页随程序打包，不下载外部前端。
- 使用 443 端口申请证书，安装到固定目录，每天自动检查续期 4 次。
- 配置服务、开机启动及防火墙，检查数据库、管理网页和 TLS，全部通过才提示成功。

后台地址：`https://你的域名`，管理员用户名：`admin`。首个客户端账号信息保存在服务器的 `/root/trojan-access.txt`，仅 root 可读。

**证书申请要求域名解析正确、443 端口能从公网访问。** 软件无法替代云厂商控制台的安全组设置。

## 更新

在已经安装的服务器上再次执行同一条一键命令。脚本保留现有数据库连接、用户和管理员密码，不会把旧数据库数据目录升级到新镜像。更新前备份程序、配置和证书；服务验证失败时恢复旧版本。

指定版本：

```bash
bash /tmp/trojan-install.sh --version v2026.10.02.000000 --update --yes
```

无人值守首次安装需提前设置 `TROJAN_ADMIN_PASSWORD`，并提供 `--domain`。不要把真实密码写入公共脚本或 GitHub 仓库。

可选 `--email 联系邮箱`。默认采用 TLS-ALPN / 443 验证；使用 `--http` 可改为 HTTP / 80 验证，此时公网还需放行 80/TCP。自有可信证书可使用 `--cert-file` 和 `--key-file`；自定义证书由使用者负责续期。

APT 源备份在 `/var/backups/trojan-apt-*`，程序备份在 `/var/backups/trojan-install-*`。服务日志：`journalctl -u trojan -n 100 --no-pager`；续期日志：`/var/log/trojan-cert-renew.log`。

## 构建与发布

GitHub Actions 使用 Debian 13 x64 构建环境，执行测试后生成完整安装包及 SHA256 校验文件。`master` 分支每次更新并通过构建后，自动在本仓库发布新版本；安装入口下载最新发布版本。

也可以在 Debian 13 x64 构建环境执行：

```bash
docker build -f scripts/build-env.Dockerfile -t trojan-build .
docker run --rm -v "$PWD:/src" trojan-build bash scripts/build-debian.sh dev
```

源代码的 GPL 许可证与版权声明保留，第三方来源及固定版本见 `THIRD_PARTY_NOTICES`。
