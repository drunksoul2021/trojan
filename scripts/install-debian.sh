#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
bundle=$(cd "$(dirname "$0")/.." && pwd)
home=/usr/local/lib/trojan-manager
config=/usr/local/etc/trojan/config.json
domain=""; email=""; yes=0; mode=alpn; cert_file=""; key_file=""
while (($#)); do
    case "$1" in
        --domain) domain="${2:?}"; shift 2 ;;
        --email) email="${2:?}"; shift 2 ;;
        --yes) yes=1; shift ;;
        --update) shift ;;
        --http) mode=standalone; shift ;;
        --cert-file) cert_file="${2:?}"; shift 2 ;;
        --key-file) key_file="${2:?}"; shift 2 ;;
        *) echo "不支持的安装参数: $1" >&2; exit 1 ;;
    esac
done
[[ $(id -u) == 0 ]] || { echo "请使用 root 运行。" >&2; exit 1; }
. /etc/os-release
[[ "$ID" == debian && "$VERSION_ID" == 13 && $(uname -m) == x86_64 ]] ||
    { echo "仅支持 Debian 13 x64。" >&2; exit 1; }
exec 9>/run/trojan-install.lock
flock -n 9 || { echo "已有安装任务正在运行。" >&2; exit 1; }
existing=0
[[ ! -s "$config" ]] || existing=1
if [[ -z "$domain" && $existing == 1 ]]; then
    domain=$(python3 -c 'import json; print(json.load(open("/usr/local/etc/trojan/config.json"))["ssl"].get("sni",""))')
fi
if [[ -z "$domain" ]]; then
    [[ $yes == 0 ]] || { echo "--yes 模式必须提供 --domain。" >&2; exit 1; }
    read -r -p "请输入指向本机的域名: " domain </dev/tty
fi
python3 - "$bundle" "$domain" <<'PY'
import sys
sys.path.insert(0,sys.argv[1]+"/scripts")
from configure import valid_domain
valid_domain(sys.argv[2])
PY
if [[ -n "$cert_file" || -n "$key_file" ]]; then
    [[ -n "$cert_file" && -n "$key_file" ]] || { echo "自定义证书需同时提供 --cert-file 与 --key-file。" >&2; exit 1; }
    python3 "$bundle/scripts/configure.py" validate-cert "$cert_file" "$key_file" "$domain"
else
    public_ip=$(curl -4 -fsS --connect-timeout 10 --max-time 20 https://api.ipify.org ||
                curl -4 -fsS --connect-timeout 10 --max-time 20 https://icanhazip.com)
    public_ip=$(echo "$public_ip" | tr -d '\r\n')
    python3 "$bundle/scripts/configure.py" dns "$domain" "$public_ip"
fi
if [[ $existing == 0 && -z "${TROJAN_ADMIN_PASSWORD:-}" ]]; then
    [[ $yes == 0 ]] || { echo "首次无人值守安装必须设置 TROJAN_ADMIN_PASSWORD。" >&2; exit 1; }
    read -r -s -p "请输入管理后台 admin 密码（至少 12 位）: " TROJAN_ADMIN_PASSWORD </dev/tty
    echo
    read -r -s -p "请再次输入密码: " confirm </dev/tty
    echo
    [[ "$TROJAN_ADMIN_PASSWORD" == "$confirm" ]] || { echo "两次密码不一致。" >&2; exit 1; }
fi
admin_password=${TROJAN_ADMIN_PASSWORD:-}
if [[ $existing == 0 && ${#admin_password} -lt 12 ]]; then
    echo "管理员密码至少 12 位。" >&2; exit 1
fi
python3 "$bundle/scripts/apt-sources.py"
apt-get -o Acquire::ForceIPv4=true update
DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y \
    docker.io ca-certificates curl python3 openssl socat cron iproute2 \
    libboost-system1.83.0 libboost-program-options1.83.0 libmariadb3 libssl3t64
systemctl enable --now docker.service
docker info >/dev/null
# Download and verify before stopping any live service.
"$bundle/manager" version >/dev/null
"$bundle/trojan-core" -v >/dev/null
if [[ $existing == 0 ]]; then
    docker pull mariadb:11.4
    if docker container inspect trojan-mariadb >/dev/null 2>&1; then
        echo "检测到已有 trojan-mariadb，但缺少配置文件。请恢复配置后再运行，数据不会覆盖。" >&2; exit 1
    fi
    if ss -lnt '( sport = :3307 )' | tail -n +2 | grep -q .; then
        echo "本机 3307 端口已占用，请先处理端口冲突。" >&2; exit 1
    fi
fi
backup="/var/backups/trojan-install-$(date -u +%Y%m%dT%H%M%S)-$$"
mkdir -p "$backup"
paths=(/usr/local/bin/trojan /usr/local/lib/trojan-manager /usr/local/etc/trojan \
       /etc/systemd/system/trojan.service /etc/systemd/system/trojan-web.service \
       /etc/cron.d/trojan-cert-renew /root/.acme.sh /etc/systemd/system/trojan-firewall.service)
for path in "${paths[@]}"; do
    if [[ -e "$path" ]]; then
        mkdir -p "$backup$(dirname "$path")"; cp -a "$path" "$backup$path"
    fi
done
crontab -l > "$backup/root.crontab" 2>/dev/null || true
was_trojan=0; was_web=0
if systemctl is-active --quiet trojan.service; then was_trojan=1; fi
if systemctl is-active --quiet trojan-web.service; then was_web=1; fi
rollback() {
    status=$?
    if [[ $status != 0 ]]; then
        echo "安装失败，正在恢复已有程序、证书和配置。备份: $backup" >&2
        systemctl stop trojan.service trojan-web.service >/dev/null 2>&1 || true
        for path in "${paths[@]}"; do
            if [[ -e "$backup$path" ]]; then
                rm -rf "$path"; mkdir -p "$(dirname "$path")"; cp -a "$backup$path" "$path"
            elif [[ $existing == 0 && "$path" != /root/.acme.sh && "$path" != /usr/local/etc/trojan ]]; then rm -rf "$path"; fi
        done
        crontab "$backup/root.crontab" || true
        systemctl daemon-reload
        if [[ $was_trojan == 1 ]]; then systemctl start trojan.service || true; fi
        if [[ $was_web == 1 ]]; then systemctl start trojan-web.service || true; fi
        echo "数据库目录保留，重新安装不会清空用户数据。" >&2
    fi
    exit "$status"
}
trap rollback EXIT
systemctl stop trojan.service trojan-web.service >/dev/null 2>&1 || true
mkdir -p "$home" /usr/local/etc/trojan
install -m 755 "$bundle/manager" /usr/local/bin/trojan
install -m 755 "$bundle/trojan-core" "$home/trojan-core"
cp -a "$bundle/scripts" "$bundle/acme.sh" "$home/"
install -m 644 "$bundle/asset/trojan.service" /etc/systemd/system/trojan.service
install -m 644 "$bundle/asset/trojan-web.service" /etc/systemd/system/trojan-web.service
systemctl daemon-reload
if [[ $existing == 0 ]]; then
    db_password=$(openssl rand -hex 24)
    root_password=$(openssl rand -hex 24)
    python3 "$home/scripts/configure.py" init "$config" "$domain" "$db_password"
    mkdir -p /var/lib/trojan-mariadb
    cat > "$backup/mariadb.env" <<EOF
MARIADB_ROOT_PASSWORD=$root_password
MARIADB_DATABASE=trojan
MARIADB_USER=trojan
MARIADB_PASSWORD=$db_password
EOF
    docker run -d --name trojan-mariadb --restart unless-stopped \
        -p 127.0.0.1:3307:3306 -v /var/lib/trojan-mariadb:/var/lib/mysql \
        --env-file "$backup/mariadb.env" mariadb:11.4 \
        --innodb-buffer-pool-size=32M --performance-schema=OFF --max-connections=40 >/dev/null
fi
TROJAN_ADMIN_PASSWORD="${TROJAN_ADMIN_PASSWORD:-}" /usr/local/bin/trojan setup
bash "$home/scripts/firewall.sh"
if [[ -n "$cert_file" ]]; then
    cert_dir=/usr/local/etc/trojan/certs
    mkdir -p "$cert_dir"; chmod 700 "$cert_dir"
    install -m 600 "$key_file" "$cert_dir/private.key"
    install -m 644 "$cert_file" "$cert_dir/fullchain.pem"
    python3 "$home/scripts/configure.py" tls "$config" "$cert_dir/fullchain.pem" "$cert_dir/private.key" "$domain"
else
    cert_args=(--domain "$domain")
    [[ -z "$email" ]] || cert_args+=(--email "$email")
    [[ "$mode" != standalone ]] || cert_args+=(--http)
    bash "$home/scripts/certificates.sh" "${cert_args[@]}"
fi
install -m 644 "$bundle/asset/trojan-firewall.service" /etc/systemd/system/trojan-firewall.service
systemctl daemon-reload
systemctl enable trojan.service trojan-web.service trojan-firewall.service
systemctl restart trojan-web.service
systemctl restart trojan.service
for attempt in $(seq 1 15); do
    if systemctl is-active --quiet trojan.service && systemctl is-active --quiet trojan-web.service &&
       curl -4 -fsS --max-time 3 http://127.0.0.1:80/auth/check >/dev/null; then break; fi
    if [[ $attempt == 15 ]]; then echo "服务启动检查失败。" >&2; exit 1; fi
    sleep 1
done
sleep 2
systemctl is-active --quiet trojan.service
listen_port=$(python3 -c 'import json; print(json.load(open("/usr/local/etc/trojan/config.json"))["local_port"])')
timeout 10 openssl s_client -connect "127.0.0.1:$listen_port" -servername "$domain" \
    -verify_hostname "$domain" -verify_return_error -brief < /dev/null > "$backup/tls-check.log" 2>&1
trap - EXIT
echo "安装成功：服务与 TLS 验证已通过。"
echo "管理后台：https://$domain:$listen_port"
echo "管理员：admin（已有管理员密码保留）"
echo "首次客户端信息保存在 /root/trojan-access.txt，仅 root 可读。"
echo "已有程序和配置备份：$backup"
echo "云厂商防火墙需允许 $listen_port/TCP；证书续期还需 443/TCP。"
