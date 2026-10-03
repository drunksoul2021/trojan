FROM node:22-bookworm-slim AS management-ui
WORKDIR /src/frontend
COPY frontend/package*.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
ENV NODE_OPTIONS=--max-old-space-size=512
RUN npm run build

FROM debian:trixie
RUN apt-get -o Acquire::ForceIPv4=true update && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y --no-install-recommends golang-go git cmake make g++ libboost-system-dev libboost-program-options-dev libssl-dev libmariadb-dev pkg-config ca-certificates python3 openssl shellcheck && rm -rf /var/lib/apt/lists/*
ENV GOMAXPROCS=1 GOMEMLIMIT=96MiB GOGC=50
COPY --from=management-ui /src/web/templates/ /opt/trojan-management-ui/
WORKDIR /src
