#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
home=${TROJAN_MANAGER_HOME:-/usr/local/lib/trojan-manager}
config=${TROJAN_CONFIG_PATH:-/usr/local/etc/trojan/config.json}
acme_home=${TROJAN_ACME_HOME:-/root/.acme.sh}
domain=""; email=""; mode=alpn
while (($#)); do
    case "$1" in
        --domain) domain="${2:?}"; shift 2 ;;
        --email) email="${2:?}"; shift 2 ;;
        --http) mode=standalone; shift ;;
        *) echo "证书参数不支持: $1" >&2; exit 1 ;;
    esac
done
python3 - "$domain" "$home" <<'PY'
import sys
sys.path.insert(0,sys.argv[2]+"/scripts")
from configure import valid_domain
valid_domain(sys.argv[1])
PY
mkdir -p "$acme_home"
install -m 700 "$home/acme.sh/acme.sh" "$acme_home/acme.sh"
hook="$home/scripts/cert-hook.sh"
pre="bash $hook pre"; post="bash $hook post"; challenge_port=443
if [[ "$mode" == standalone ]]; then
    pre="/usr/bin/systemctl stop trojan-web.service"
    post="/usr/bin/systemctl start trojan-web.service"
    challenge_port=80
fi
opts=()
if [[ -n "$email" ]]; then opts+=(--accountemail "$email"); fi
profile="$acme_home/${domain}_ecc/$domain.conf"
if [[ -s "$profile" && -s "$acme_home/${domain}_ecc/fullchain.cer" ]]; then
    encoded_pre=$(printf '%s' "$pre" | base64 -w0)
    encoded_post=$(printf '%s' "$post" | base64 -w0)
    if ! grep -Fxq "Le_Webroot='$mode'" "$profile" ||
       ! grep -Fxq "Le_PreHook='__ACME_BASE64__START_${encoded_pre}__ACME_BASE64__END_'" "$profile" ||
       ! grep -Fxq "Le_PostHook='__ACME_BASE64__START_${encoded_post}__ACME_BASE64__END_'" "$profile"; then
        opts+=(--force)
        echo "正在迁移证书验证方式及续期钩子，仅首次迁移重新签发。"
    fi
fi
issue_status=0
bash "$acme_home/acme.sh" --issue "--$mode" --listen-v4 -d "$domain" --server letsencrypt \
    --keylength ec-256 --pre-hook "$pre" --post-hook "$post" "${opts[@]}" || issue_status=$?
if [[ $issue_status != 0 && $issue_status != 2 ]]; then
    echo "证书申请失败。请检查域名解析以及公网 $challenge_port 端口；已有证书和配置未替换。" >&2
    exit 1
fi
source_cert="$acme_home/${domain}_ecc/fullchain.cer"
source_key="$acme_home/${domain}_ecc/$domain.key"
python3 "$home/scripts/configure.py" validate-cert "$source_cert" "$source_key" "$domain"
cert_dir="$(dirname "$config")/certs"
mkdir -p "$cert_dir"; chmod 700 "$cert_dir"
touch /run/trojan-certificate-installing
trap 'rm -f /run/trojan-certificate-installing' EXIT
bash "$acme_home/acme.sh" --install-cert -d "$domain" --ecc \
    --key-file "$cert_dir/private.key" --fullchain-file "$cert_dir/fullchain.pem" \
    --reloadcmd "bash $hook reload"
python3 "$home/scripts/configure.py" tls "$config" "$cert_dir/fullchain.pem" "$cert_dir/private.key" "$domain"
chmod 600 "$cert_dir/private.key"
rm -f /run/trojan-certificate-installing
cat > /etc/cron.d/trojan-cert-renew <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
17 2,8,14,20 * * * root /usr/bin/flock -n /run/trojan-cert-renew.lock bash $acme_home/acme.sh --cron --home $acme_home >> /var/log/trojan-cert-renew.log 2>&1
EOF
chmod 644 /etc/cron.d/trojan-cert-renew
systemctl enable --now cron.service
if crontab -l >/dev/null 2>&1; then
    crontab -l | sed '\|/root/.acme.sh.*--cron|d' | crontab -
fi
echo "证书已安装，自动续期检查已配置。"
