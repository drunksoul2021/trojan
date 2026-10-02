import importlib.util, json, os, pathlib, socket, subprocess, tempfile, unittest
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/f'{name}.py')
    m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
cfg=module('configure'); apt=module('apt-sources')
class ConfigurationTests(unittest.TestCase):
    def test_domain_rejects_commands_and_ip(self):
        for value in ['','localhost','1.2.3.4','example.com;touch /tmp/x','-bad.example.com']:
            with self.subTest(value=value),self.assertRaises(ValueError): cfg.valid_domain(value)
        self.assertEqual(cfg.valid_domain('Server.Example.COM'),'server.example.com')
    def test_dns_ipv4_matches_and_ipv6_is_explicit(self):
        def lookup(host,port,family,*args):
            if family==socket.AF_INET: return [(family,1,6,'',('1.2.3.4',port))]
            raise socket.gaierror()
        with patch.object(socket,'getaddrinfo',side_effect=lookup):
            cfg.check_dns('server.example.com','1.2.3.4')
            with self.assertRaises(ValueError): cfg.check_dns('server.example.com','1.2.3.5')
        with patch.object(socket,'getaddrinfo',return_value=[(2,1,6,'',('1.2.3.4',443))]):
            with self.assertRaisesRegex(ValueError,'AAAA'): cfg.check_dns('server.example.com','1.2.3.4')
    def test_atomic_config_preserves_secrets_and_restricts_permissions(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d)/'config.json'; data={'password':['original'],'mysql':{'password':'unchanged'}}
            cfg.atomic_json(p,data)
            self.assertEqual(json.loads(p.read_text()),data)
            self.assertEqual(p.stat().st_mode&0o777,0o600)
    def test_apt_repair_mixed_sources_and_idempotency(self):
        with tempfile.TemporaryDirectory() as d:
            r=pathlib.Path(d); a=r/'etc/apt'; parts=a/'sources.list.d'; parts.mkdir(parents=True)
            old='deb http://deb.debian.org/debian trixie main\ndeb https://packages.vendor.test/stable main\n'
            (a/'sources.list').write_text(old)
            (parts/'debian.sources').write_text('Types: deb\nURIs: https://deb.debian.org/debian\nSuites: trixie\nSigned-By: /wrong/key\n')
            vendor='Types: deb\nURIs: https://packages.vendor.test/stable\nSuites: stable\nComponents: main\nSigned-By: /vendor/key\n'
            (parts/'vendor.sources').write_text(vendor)
            backup=apt.repair(r)
            self.assertEqual((backup/'etc/apt/sources.list').read_text(),old)
            self.assertEqual((parts/'vendor.sources').read_text(),vendor)
            self.assertNotIn('deb.debian.org',(a/'sources.list').read_text())
            self.assertEqual((parts/'trojan-debian13.sources').read_text(),apt.CANONICAL)
            self.assertIsNone(apt.repair(r))
class CertificateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory(); cls.root=pathlib.Path(cls.tmp.name)
        cls.cert=str(cls.root/'cert.pem'); cls.key=str(cls.root/'key.pem')
        subprocess.run(['openssl','req','-x509','-newkey','ec','-pkeyopt','ec_paramgen_curve:P-256',
            '-nodes','-keyout',cls.key,'-out',cls.cert,'-days','2','-subj','/CN=server.example.com',
            '-addext','subjectAltName=DNS:server.example.com'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        cls.other=str(cls.root/'other.key')
        subprocess.run(['openssl','genpkey','-algorithm','EC','-pkeyopt','ec_paramgen_curve:P-256','-out',cls.other],check=True,stderr=subprocess.DEVNULL)
    @classmethod
    def tearDownClass(cls): cls.tmp.cleanup()
    def test_valid_certificate(self): cfg.validate_certificate(self.cert,self.key,'server.example.com')
    def test_wrong_hostname_rejected(self):
        with self.assertRaises(ValueError): cfg.validate_certificate(self.cert,self.key,'wrong.example.com')
    def test_wrong_key_rejected(self):
        with self.assertRaises(ValueError): cfg.validate_certificate(self.cert,self.other,'server.example.com')
    def test_missing_certificate_does_not_modify_config(self):
        p=self.root/'preserved.json'; cfg.atomic_json(p,{'password':['keep'],'ssl':{'cert':'previous'}}); before=p.read_bytes()
        result=subprocess.run(['python3',str(ROOT/'scripts/configure.py'),'tls',str(p),str(self.root/'missing'),self.key,'server.example.com'],capture_output=True)
        self.assertNotEqual(result.returncode,0); self.assertEqual(p.read_bytes(),before)
    def test_failed_issuance_does_not_write_config(self):
        with tempfile.TemporaryDirectory() as d:
            r=pathlib.Path(d); h=r/'manager'; (h/'scripts').mkdir(parents=True); (h/'acme.sh').mkdir()
            import shutil
            shutil.copy(ROOT/'scripts/configure.py',h/'scripts/configure.py')
            (h/'acme.sh/acme.sh').write_text('#!/bin/bash\nexit 1\n')
            p=r/'config.json'; p.write_text('{"ssl":{"cert":"previous"}}'); before=p.read_bytes()
            env=dict(os.environ,TROJAN_MANAGER_HOME=str(h),TROJAN_CONFIG_PATH=str(p),TROJAN_ACME_HOME=str(r/'acme'))
            result=subprocess.run(['bash',str(ROOT/'scripts/certificates.sh'),'--domain','server.example.com'],env=env,capture_output=True)
            self.assertNotEqual(result.returncode,0); self.assertEqual(p.read_bytes(),before)
            self.assertIn('已有证书和配置未替换',result.stderr.decode())
if __name__=='__main__': unittest.main()
