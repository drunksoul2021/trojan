#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
home=/usr/local/lib/trojan-manager
certs=/usr/local/etc/trojan/certs
state=/run/trojan-cert-renew.state
case "${1:-}" in
    pre)
        mkdir -p "$certs/previous"
        for f in fullchain.pem private.key; do
            [[ ! -s "$certs/$f" ]] || cp -p "$certs/$f" "$certs/previous/$f"
        done
        if systemctl is-active --quiet trojan.service; then
            echo active > "$state"; systemctl stop trojan.service
        else echo inactive > "$state"; fi ;;
    post)
        if [[ -f "$state" && $(cat "$state") == active ]]; then systemctl start trojan.service; fi ;;
    reload)
        [[ ! -f /run/trojan-certificate-installing ]] || exit 0
        domain=$(python3 -c 'import json; print(json.load(open("/usr/local/etc/trojan/config.json"))["ssl"]["sni"])')
        if ! python3 "$home/scripts/configure.py" validate-cert "$certs/fullchain.pem" "$certs/private.key" "$domain"; then
            for f in fullchain.pem private.key; do
                [[ ! -s "$certs/previous/$f" ]] || cp -p "$certs/previous/$f" "$certs/$f"
            done
            systemctl restart trojan.service; exit 1
        fi
        chmod 600 "$certs/private.key"
        systemctl restart trojan.service
        if systemctl is-active --quiet trojan-web.service; then systemctl restart trojan-web.service; fi ;;
    *) echo "用法: cert-hook.sh pre|post|reload" >&2; exit 1 ;;
esac
