#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
name="trojan-install-smoke-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker build -f scripts/test-systemd.Dockerfile -t trojan-debian13-test .
docker run -dt --name "$name" --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock trojan-debian13-test >/dev/null
docker cp dist/bundle "$name:/opt/bundle"
docker cp tests/test_running_api.py "$name:/opt/test_running_api.py"
for n in $(seq 1 30); do
 if docker exec "$name" systemctl is-system-running 2>/dev/null | grep -Eq 'running|degraded'; then break; fi
 sleep 1
done
docker exec "$name" openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout /root/test.key -out /root/test.pem -days 2 -subj /CN=server.example.com -addext subjectAltName=DNS:server.example.com
install_test() {
 docker exec -e TROJAN_ADMIN_PASSWORD="$1" -e SSL_CERT_FILE=/root/test.pem "$name" bash /opt/bundle/scripts/install-debian.sh --domain server.example.com --admin-user smoke-admin --cert-file /root/test.pem --key-file /root/test.key --yes
}
install_test test-admin-password-123
docker exec "$name" python3 /opt/test_running_api.py
install_test different-password-456
docker exec "$name" python3 /opt/test_running_api.py
# Force a service failure after files were replaced, then verify rollback.
docker exec "$name" bash -c 'printf "#!/bin/bash\n[[ \"\$1\" == -v ]] && exit 0\nexit 1\n" > /opt/bundle/trojan-core; chmod 755 /opt/bundle/trojan-core'
if install_test different-password-456; then echo "Failed kernel was accepted" >&2; exit 1; fi
docker exec "$name" systemctl is-active --quiet trojan.service
docker exec "$name" python3 /opt/test_running_api.py
echo FULL_INSTALL_REPEAT_AND_ROLLBACK_OK
