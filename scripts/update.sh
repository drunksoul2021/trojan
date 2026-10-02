#!/usr/bin/env bash
set -Eeuo pipefail
file=$(mktemp /tmp/trojan-update.XXXXXXXX)
trap 'rm -f "$file"' EXIT
curl -4 -fsSL --retry 3 --connect-timeout 15 --max-time 60 https://raw.githubusercontent.com/drunksoul2021/trojan/master/install.sh -o "$file"
bash "$file" --update --yes "$@"
