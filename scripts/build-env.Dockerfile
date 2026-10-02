FROM debian:trixie
RUN apt-get -o Acquire::ForceIPv4=true update && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y --no-install-recommends golang-go git cmake make g++ libboost-system-dev libboost-program-options-dev libssl-dev libmariadb-dev pkg-config ca-certificates python3 openssl shellcheck && rm -rf /var/lib/apt/lists/*
ENV GOMAXPROCS=1 GOMEMLIMIT=96MiB GOGC=50
WORKDIR /src
