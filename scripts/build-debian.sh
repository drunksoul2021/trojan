#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
version=${1:-dev}
mkdir -p dist/bundle web/templates
cp -a /opt/trojan-management-ui/. web/templates/
GOMAXPROCS=1 CGO_ENABLED=0 go test -buildvcs=false -trimpath -p 1 -tags nomsgpack ./...
GOMAXPROCS=1 CGO_ENABLED=0 go build -buildvcs=false -p 1 -trimpath -tags nomsgpack -ldflags "-s -w -X trojan/trojan.MVersion=$version -X trojan/trojan.GitVersion=$(git -c safe.directory="$PWD" rev-parse HEAD)" -o dist/bundle/manager .
cmake -S third_party/trojan-core -B dist/core -DCMAKE_BUILD_TYPE=Release -DENABLE_MYSQL=ON -DSYSTEMD_SERVICE=OFF
cmake --build dist/core --parallel 1
cp dist/core/trojan dist/bundle/trojan-core
cp -a scripts asset dist/bundle/
cp -a third_party/acme.sh dist/bundle/acme.sh
cp LICENSE dist/bundle/
tar -czf dist/trojan-debian13-amd64.tar.gz -C dist/bundle .
(cd dist && sha256sum trojan-debian13-amd64.tar.gz > SHA256SUMS)
echo BUILD_COMPLETE
