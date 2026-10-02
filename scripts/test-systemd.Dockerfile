FROM debian:trixie
ENV container=docker
RUN apt-get -o Acquire::ForceIPv4=true update && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y --no-install-recommends systemd systemd-sysv dbus docker.io docker-cli python3 curl openssl ca-certificates && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
