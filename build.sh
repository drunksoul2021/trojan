#!/usr/bin/env bash
set -Eeuo pipefail
exec bash "$(dirname "$0")/scripts/build-debian.sh" "$@"
