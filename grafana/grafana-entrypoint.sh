#!/usr/bin/env sh
set -eu

export GF_SERVER_HTTP_PORT="${PORT:-3000}"
export GF_SERVER_DOMAIN="${RAILWAY_PUBLIC_DOMAIN:-localhost}"
export GF_SERVER_ROOT_URL="${GF_SERVER_ROOT_URL:-https://${GF_SERVER_DOMAIN}}"

exec /run.sh
