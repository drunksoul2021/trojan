#!/usr/bin/env bash
set -Eeuo pipefail
port=$(python3 -c 'import json; print(json.load(open("/usr/local/etc/trojan/config.json"))["local_port"])')
ports=(443 "$port")
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
    for p in "${ports[@]}"; do ufw allow "$p/tcp" comment 'Trojan TLS'; done
elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
    for p in "${ports[@]}"; do firewall-cmd --permanent --add-port="$p/tcp"; done
    firewall-cmd --reload
elif command -v nft >/dev/null; then
    python3 - "$port" <<'PY'
import json,re,subprocess,sys
r=subprocess.run(["nft","-j","list","ruleset"],capture_output=True,text=True)
if r.returncode: raise SystemExit(r.stderr)
data=json.loads(r.stdout)["nftables"]
for item in data:
    c=item.get("chain",{})
    if c.get("hook")!="input" or c.get("policy")!="drop" or c.get("family") not in ("ip","inet"): continue
    family,table,chain=c["family"],c["table"],c["name"]
    if not all(re.fullmatch(r"[A-Za-z0-9_.-]+",x) for x in (table,chain)): raise SystemExit("防火墙链名不支持自动配置。")
    for port in sorted({443,int(sys.argv[1])}):
        comment=f"trojan-tcp-{port}"
        if any(i.get("rule",{}).get("comment")==comment and i["rule"].get("table")==table
               and i["rule"].get("chain")==chain for i in data): continue
        subprocess.run(["nft","insert","rule",family,table,chain,"tcp","dport",str(port),
                        "accept","comment",f'"{comment}"'],check=True)
PY
elif command -v iptables >/dev/null; then
    for p in "${ports[@]}"; do
        iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null ||
            iptables -I INPUT -p tcp --dport "$p" -j ACCEPT
    done
fi
