#!/usr/bin/env sh
set -eu

export GF_SERVER_HTTP_PORT="${PORT:-3000}"
export GF_SERVER_DOMAIN="${RAILWAY_PUBLIC_DOMAIN:-localhost}"
export GF_SERVER_ROOT_URL="${GF_SERVER_ROOT_URL:-https://${GF_SERVER_DOMAIN}}"

mkdir -p /var/lib/grafana/plugins
chown -R 472:0 /var/lib/grafana

exec su-exec 472:0 /run.sh
