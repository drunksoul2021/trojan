#!/usr/bin/env python3
"""Atomic configuration and IPv4/certificate validation."""
import argparse, hashlib, ipaddress, json, os, pathlib, socket, subprocess, tempfile

def atomic_json(path, data):
    path=pathlib.Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    fd,name=tempfile.mkstemp(prefix='.config-',dir=path.parent)
    try:
        with os.fdopen(fd,'w') as f:
            json.dump(data,f,indent=2); f.write('\n'); f.flush(); os.fsync(f.fileno())
        os.chmod(name,0o600); os.replace(name,path)
    finally:
        if os.path.exists(name): os.unlink(name)

def valid_domain(domain):
    import re
    if not domain or len(domain)>253 or '.' not in domain:
        raise ValueError('请输入完整域名，例如 server.example.com。')
    if not all(re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?',p) for p in domain.split('.')):
        raise ValueError('域名格式不正确。')
    try: ipaddress.ip_address(domain)
    except ValueError: return domain.lower()
    raise ValueError('证书申请需要域名，不能填写 IP 地址。')

def check_dns(domain, public_ip):
    valid_domain(domain)
    addresses={x[4][0] for x in socket.getaddrinfo(domain,443,socket.AF_INET,socket.SOCK_STREAM)}
    if not addresses or addresses != {public_ip}:
        raise ValueError(f'域名 A 记录为 {sorted(addresses)}，请只指向服务器公网 IPv4 {public_ip}。')
    try: ipv6={x[4][0] for x in socket.getaddrinfo(domain,443,socket.AF_INET6,socket.SOCK_STREAM)}
    except socket.gaierror: ipv6=set()
    if ipv6:
        raise ValueError('IPv4 模式检测到 AAAA 记录，请先移除该域名的 AAAA 记录，避免客户端或证书验证走 IPv6。')

def validate_certificate(cert,key,domain):
    for path in (cert,key):
        if not pathlib.Path(path).is_file() or pathlib.Path(path).stat().st_size == 0:
            raise ValueError('证书或私钥文件不存在 / 为空，已有配置未修改。')
    def run(args): return subprocess.check_output(args,stderr=subprocess.PIPE)
    run(['openssl','x509','-in',cert,'-noout','-checkend','86400'])
    try: result=run(['openssl','x509','-in',cert,'-noout','-checkhost',domain]).decode()
    except subprocess.CalledProcessError as e: raise ValueError('证书域名不匹配。') from e
    if 'does match certificate' not in result: raise ValueError('证书域名不匹配。')
    public=run(['openssl','x509','-in',cert,'-pubkey','-noout'])
    private_public=run(['openssl','pkey','-in',key,'-pubout'])
    if hashlib.sha256(public).digest()!=hashlib.sha256(private_public).digest():
        raise ValueError('证书与私钥不匹配，已有配置未修改。')

def main():
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest='command',required=True)
    s=sub.add_parser('dns'); s.add_argument('domain'); s.add_argument('public_ip')
    s=sub.add_parser('validate-cert'); s.add_argument('cert'); s.add_argument('key'); s.add_argument('domain')
    s=sub.add_parser('tls'); s.add_argument('config'); s.add_argument('cert'); s.add_argument('key'); s.add_argument('domain')
    s=sub.add_parser('init'); s.add_argument('config'); s.add_argument('domain'); s.add_argument('db_password')
    a=p.parse_args()
    if a.command=='dns': check_dns(a.domain,a.public_ip)
    elif a.command=='validate-cert': validate_certificate(a.cert,a.key,a.domain)
    elif a.command=='tls':
        validate_certificate(a.cert,a.key,a.domain)
        data=json.loads(pathlib.Path(a.config).read_text())
        data.setdefault('ssl',{}).update(cert=a.cert,key=a.key,sni=a.domain)
        data.setdefault('tcp',{})['prefer_ipv4']=True
        atomic_json(a.config,data)
    else:
        valid_domain(a.domain)
        if pathlib.Path(a.config).exists(): raise ValueError('已有配置不允许覆盖。')
        atomic_json(a.config,{'run_type':'server','local_addr':'0.0.0.0','local_port':443,
            'remote_addr':'127.0.0.1','remote_port':80,'password':[],'log_level':1,
            'ssl':{'cert':'','key':'','sni':a.domain,'alpn':['http/1.1'],'reuse_session':True,
                   'session_ticket':False,'session_timeout':600},
            'tcp':{'prefer_ipv4':True,'no_delay':True,'keep_alive':True},
            'mysql':{'enabled':True,'server_addr':'127.0.0.1','server_port':3307,
                     'database':'trojan','username':'trojan','password':a.db_password}})
if __name__=='__main__':
    try: main()
    except (ValueError,OSError,subprocess.CalledProcessError) as e:
        raise SystemExit('校验失败: '+(str(e) if not isinstance(e,subprocess.CalledProcessError) else '证书解析、有效期或域名校验不通过。'))
