#!/usr/bin/env python3
"""Back up and repair Debian sources; preserve third-party repositories."""
import argparse,datetime,pathlib,re,shutil
CANONICAL='''Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://deb.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
'''
def is_debian(text):
    return bool(re.search(r'(?:deb\.debian\.org|security\.debian\.org|ftp\.[\w.-]*debian\.org|/debian(?:-security)?(?:/|\s|$))',text))

def repair(root=pathlib.Path('/')):
    root=pathlib.Path(root)
    apt=root/'etc/apt'; parts=apt/'sources.list.d'; parts.mkdir(parents=True,exist_ok=True)
    files=([apt/'sources.list'] if (apt/'sources.list').exists() else [])+list(parts.glob('*.list'))+list(parts.glob('*.sources'))
    edits={}; target=parts/'trojan-debian13.sources'
    for f in files:
        if f==target: continue
        text=f.read_text()
        if not is_debian(text): continue
        if f.suffix=='.sources':
            chunks=re.split(r'\n\s*\n',text); kept=[]
            for chunk in chunks:
                if not chunk.strip(): continue
                if is_debian(chunk):
                    uri=re.search(r'^URIs:\s*(.*)$',chunk,re.M)
                    if uri:
                        remaining=[u for u in uri[1].split() if not is_debian(u)]
                        if remaining:
                            chunk=re.sub(r'^URIs:.*$', 'URIs: '+' '.join(remaining),chunk,flags=re.M)
                            kept.append(chunk)
                else: kept.append(chunk)
            new='\n\n'.join(kept)+('\n' if kept else '')
        else:
            new=''.join(line for line in text.splitlines(keepends=True)
                        if line.lstrip().startswith('#') or not is_debian(line))
        if new!=text: edits[f]=new
    if not target.exists() or target.read_text()!=CANONICAL: edits[target]=CANONICAL
    ipv4=apt/'apt.conf.d/99trojan-ipv4'; ipv4.parent.mkdir(parents=True,exist_ok=True)
    if not ipv4.exists() or ipv4.read_text()!='Acquire::ForceIPv4 "true";\n':
        edits[ipv4]='Acquire::ForceIPv4 "true";\n'
    if not edits: return None
    backup=root/('var/backups/trojan-apt-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    backup.mkdir(parents=True,mode=0o700)
    for f,new in edits.items():
        if f.exists():
            dest=backup/f.relative_to(root); dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(f,dest)
        f.write_text(new); f.chmod(0o644)
    return backup
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--root',default='/'); a=p.parse_args()
    b=repair(pathlib.Path(a.root))
    print('Debian 13 官方源和 IPv4 已配置。'+(f' 原配置备份: {b}' if b else ' 配置已经正确，无需重复修改。'))
