#!/usr/bin/env bash
# Independent Debian 13 bootstrap. GPL-3.0.
(
set -Eeuo pipefail
umask 077
repo=drunksoul2021/trojan
version=""
args=()
while (($#)); do
    case "$1" in
        --version) version="${2:?请提供版本号}"; shift 2 ;;
        -h|--help)
            echo "Debian 13 x64 一键安装 / 更新"
            echo "用法: bash install.sh [--domain 域名] [--email 邮箱] [--version v版本] [--yes]"
            echo "管理员密码交互输入，或通过 TROJAN_ADMIN_PASSWORD 环境变量提供。"
            exit 0 ;;
        --domain|--email|--cert-file|--key-file) args+=("$1" "${2:?缺少参数}"); shift 2 ;;
        --yes|--update|--http) args+=("$1"); shift ;;
        *) echo "不支持的参数: $1" >&2; exit 1 ;;
    esac
done
[[ $(id -u) == 0 ]] || { echo "请使用 root 或 sudo bash 运行。" >&2; exit 1; }
. /etc/os-release
[[ "$ID" == debian && "$VERSION_ID" == 13 && $(uname -m) == x86_64 ]] ||
    { echo "当前版本只支持 Debian 13 (trixie) x64。" >&2; exit 1; }
command -v systemctl >/dev/null
task_dir=$(mktemp -d /tmp/trojan-install.XXXXXXXX)
trap 'rm -rf "$task_dir"' EXIT
# Use signed official sources for bootstrap even if existing files conflict.
cat > "$task_dir/bootstrap.list" <<EOF
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian trixie main
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian trixie-updates main
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian-security trixie-security main
EOF
apt_opts=(-o Acquire::ForceIPv4=true -o "Dir::Etc::sourcelist=$task_dir/bootstrap.list" -o Dir::Etc::sourceparts=-)
apt-get "${apt_opts[@]}" update
DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" install -y ca-certificates curl python3 tar
fetch() { curl -4 --fail --show-error --silent --location --retry 3 --connect-timeout 15 --max-time 300 "$@"; }
if [[ -z "$version" ]]; then
    fetch "https://api.github.com/repos/$repo/releases/latest" -o "$task_dir/release.json"
    version=$(python3 - "$task_dir/release.json" <<'PY'
import json,sys
v=json.load(open(sys.argv[1])).get("tag_name","")
if not v or not v.startswith("v"): raise SystemExit("仓库尚未发布可用安装包。")
print(v)
PY
)
fi
[[ "$version" =~ ^v[0-9][0-9A-Za-z._-]*$ ]] || { echo "版本号不合法。" >&2; exit 1; }
archive=trojan-debian13-amd64.tar.gz
base="https://github.com/$repo/releases/download/$version"
fetch "$base/$archive" -o "$task_dir/$archive"
fetch "$base/SHA256SUMS" -o "$task_dir/SHA256SUMS"
python3 - "$task_dir" "$archive" <<'PY'
import hashlib,pathlib,sys
root=pathlib.Path(sys.argv[1]); name=sys.argv[2]
matches=[line.split() for line in (root/"SHA256SUMS").read_text().splitlines()
         if len(line.split()) == 2 and line.split()[1].lstrip("*") == name]
if len(matches)!=1 or hashlib.sha256((root/name).read_bytes()).hexdigest()!=matches[0][0]:
    raise SystemExit("安装包校验失败，已有程序未修改。")
PY
mkdir "$task_dir/bundle"
tar -xzf "$task_dir/$archive" -C "$task_dir/bundle"
bash "$task_dir/bundle/scripts/install-debian.sh" "${args[@]}"
)
