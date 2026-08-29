#!/usr/bin/env bash
#
# Railway entrypoint for every Apache Airflow role:
#
#   railway-entrypoint.sh api-server | scheduler | dag-processor | triggerer | worker
#
# It fills in what a Railway service cannot express as a plain variable, then
# hands over to the image's own entrypoint so upstream's connection checks and
# signal handling stay intact.
set -euo pipefail

HELPERS=/opt/airflow/railway_airflow

ROLE="${1:-}"
if [ -z "${ROLE}" ]; then
  echo "[railway] FATAL: no role given (api-server|scheduler|dag-processor|triggerer|worker)" >&2
  exit 64
fi
shift

log() { echo "[railway] $*"; }

# ---------------------------------------------------------------------------
# Secrets
#
# Three Airflow values must be byte-identical on every component: the Fernet key
# that decrypts stored connections, the JWT secret the task-execution API is
# signed with, and the API secret key that authorises log retrieval. A
# per-service ${{secret(N)}} resolves differently on each service, and no
# service can write another's environment, so all three are derived here from
# one seed. Each stays overridable for an operator who supplies their own.
# ---------------------------------------------------------------------------
if [ -z "${AIRFLOW_SECRET_SEED:-}" ]; then
  log "FATAL: AIRFLOW_SECRET_SEED is not set; it must hold the same value on every Airflow service"
  exit 78
fi

# 32 bytes as url-safe base64 with padding: exactly what cryptography.Fernet wants.
AIRFLOW__CORE__FERNET_KEY="${AIRFLOW__CORE__FERNET_KEY:-$(python "${HELPERS}/derive_secret.py" "${AIRFLOW_SECRET_SEED}" fernet)}"
AIRFLOW__API_AUTH__JWT_SECRET="${AIRFLOW__API_AUTH__JWT_SECRET:-$(python "${HELPERS}/derive_secret.py" "${AIRFLOW_SECRET_SEED}" jwt)}"
AIRFLOW__API__SECRET_KEY="${AIRFLOW__API__SECRET_KEY:-$(python "${HELPERS}/derive_secret.py" "${AIRFLOW_SECRET_SEED}" api)}"
export AIRFLOW__CORE__FERNET_KEY AIRFLOW__API_AUTH__JWT_SECRET AIRFLOW__API__SECRET_KEY
unset AIRFLOW_SECRET_SEED

# ---------------------------------------------------------------------------
# Metadata database and Celery broker
# ---------------------------------------------------------------------------
if [ -z "${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN:-}" ]; then
  if [ -z "${DATABASE_URL:-}" ]; then
    log "FATAL: set DATABASE_URL (or AIRFLOW__DATABASE__SQL_ALCHEMY_CONN) to the Postgres metadata database"
    exit 78
  fi
  conn="${DATABASE_URL}"
  conn="${conn/#postgresql:\/\//postgresql+psycopg2://}"
  conn="${conn/#postgres:\/\//postgresql+psycopg2://}"
  export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="${conn}"
fi
export AIRFLOW__CELERY__RESULT_BACKEND="${AIRFLOW__CELERY__RESULT_BACKEND:-db+${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN}}"

if [ -z "${AIRFLOW__CELERY__BROKER_URL:-}" ]; then
  if [ -z "${REDIS_URL:-}" ]; then
    log "FATAL: set REDIS_URL (or AIRFLOW__CELERY__BROKER_URL) to the Celery broker"
    exit 78
  fi
  broker="${REDIS_URL}"
  # Railway's REDIS_URL carries no database index; Celery wants one.
  case "${broker}" in
    */[0-9]|*/[0-9][0-9]) ;;
    *) broker="${broker%/}/0" ;;
  esac
  export AIRFLOW__CELERY__BROKER_URL="${broker}"
fi

# ---------------------------------------------------------------------------
# Task logs live in object storage. Railway volumes are 1:1, so the single
# shared logs directory upstream's compose file mounts into every container
# cannot exist here; the bucket is what lets the api-server read a log a worker
# wrote.
# ---------------------------------------------------------------------------
if [ -n "${AIRFLOW_LOGS_BUCKET:-}" ] && [ -n "${AIRFLOW_LOGS_ACCESS_KEY_ID:-}" ]; then
  export AIRFLOW__LOGGING__REMOTE_LOGGING=True
  export AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER="s3://${AIRFLOW_LOGS_BUCKET}/task-logs"
  export AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID=railway_s3
  AIRFLOW_CONN_RAILWAY_S3="$(python "${HELPERS}/s3_conn.py" \
    "${AIRFLOW_LOGS_ACCESS_KEY_ID}" "${AIRFLOW_LOGS_SECRET_ACCESS_KEY:-}" \
    "${AIRFLOW_LOGS_ENDPOINT:-}" "${AIRFLOW_LOGS_REGION:-auto}")"
  export AIRFLOW_CONN_RAILWAY_S3
  unset AIRFLOW_LOGS_SECRET_ACCESS_KEY
else
  log "no object storage configured: task logs stay on each container and are lost on redeploy"
fi

# ---------------------------------------------------------------------------
# How the other roles reach the api-server's task-execution API. The private
# hostname is deterministic, so it is defaulted here rather than shipped as a
# template variable: a ${{service.RAILWAY_PRIVATE_DOMAIN}} reference renders
# empty on a service's first-ever deployment, which is exactly when a template
# deploys every service at once.
# ---------------------------------------------------------------------------
: "${AIRFLOW_APISERVER_HOST:=airflow-apiserver.railway.internal:8080}"
case "${AIRFLOW__CORE__EXECUTION_API_SERVER_URL:-}" in
  "" | *"://:"*)
    AIRFLOW__CORE__EXECUTION_API_SERVER_URL="http://${AIRFLOW_APISERVER_HOST}/execution/" ;;
esac
export AIRFLOW__CORE__EXECUTION_API_SERVER_URL

# ---------------------------------------------------------------------------
# DAG bundles. The image always carries this repository's dags/ directory;
# AIRFLOW_DAGS_GIT_REPO_URL adds a second, versioned git bundle so a deployer
# can change DAGs without rebuilding the image.
# ---------------------------------------------------------------------------
if [ -n "${AIRFLOW_DAGS_GIT_REPO_URL:-}" ] && [ -z "${AIRFLOW__DAG_PROCESSOR__DAG_BUNDLE_CONFIG_LIST:-}" ]; then
  AIRFLOW__DAG_PROCESSOR__DAG_BUNDLE_CONFIG_LIST="$(python "${HELPERS}/dag_bundles.py" \
    "${AIRFLOW_DAGS_GIT_REPO_URL}" "${AIRFLOW_DAGS_GIT_REF:-main}" "${AIRFLOW_DAGS_GIT_SUBDIR:-dags}")"
  export AIRFLOW__DAG_PROCESSOR__DAG_BUNDLE_CONFIG_LIST
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Railway's private network routes IPv6 between services while uvicorn and the
# Airflow log servers bind IPv4. Relaying the IPv6 side of the same port onto
# 127.0.0.1 serves the IPv4 health-check prober and IPv6 peers at once.
start_ipv6_relay() {
  socat "TCP6-LISTEN:$1,ipv6only=1,fork,reuseaddr" "TCP4:127.0.0.1:$1" &
  log "IPv6 relay listening on [::]:$1"
}

# A role with no HTTP surface of its own still gets a real Railway health check
# by serving its own CLI liveness command over $PORT.
start_healthz() {
  HEALTHZ_COMMAND="$1" HEALTHZ_PORT="${PORT:-8081}" python "${HELPERS}/healthz.py" &
  log "health endpoint listening on :${PORT:-8081}/healthz"
}

# Railway has no service ordering, so every role but the api-server waits for
# the migration the api-server runs rather than racing it.
wait_for_migrations() {
  attempt=1
  while [ "${attempt}" -le 30 ]; do
    if airflow db check-migrations --migration-wait-timeout 30; then
      return 0
    fi
    log "metadata database is not migrated yet (attempt ${attempt}/30)"
    attempt=$((attempt + 1))
    sleep 5
  done
  log "FATAL: the metadata database never reached the expected schema version"
  return 1
}

bootstrap_database() {
  attempt=1
  while :; do
    if airflow db migrate; then
      break
    fi
    if [ "${attempt}" -ge 20 ]; then
      log "FATAL: airflow db migrate failed 20 times"
      return 1
    fi
    log "airflow db migrate failed (attempt ${attempt}/20), retrying"
    attempt=$((attempt + 1))
    sleep 10
  done

  admin="${AIRFLOW_ADMIN_USERNAME:-admin}"
  if [ -z "${AIRFLOW_ADMIN_PASSWORD:-}" ]; then
    log "AIRFLOW_ADMIN_PASSWORD is unset, so no administrator was created"
    return 0
  fi
  if airflow users list --output plain 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "${admin}"; then
    log "administrator ${admin} already exists; its password is left alone"
    return 0
  fi
  airflow users create \
    --username "${admin}" \
    --password "${AIRFLOW_ADMIN_PASSWORD}" \
    --firstname "${AIRFLOW_ADMIN_FIRSTNAME:-Airflow}" \
    --lastname "${AIRFLOW_ADMIN_LASTNAME:-Admin}" \
    --email "${AIRFLOW_ADMIN_EMAIL:-admin@example.com}" \
    --role Admin
  log "administrator ${admin} created"
}

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------
case "${ROLE}" in
  api-server)
    export AIRFLOW__API__HOST=0.0.0.0
    export AIRFLOW__API__PORT="${PORT:-8080}"
    if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ] && [ -z "${AIRFLOW__API__BASE_URL:-}" ]; then
      export AIRFLOW__API__BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
    fi
    bootstrap_database
    start_ipv6_relay "${AIRFLOW__API__PORT}"
    exec /usr/bin/dumb-init -- /entrypoint api-server --proxy-headers "$@"
    ;;

  scheduler)
    export AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK=True
    export AIRFLOW__SCHEDULER__SCHEDULER_HEALTH_CHECK_SERVER_PORT="${PORT:-8974}"
    wait_for_migrations
    exec /usr/bin/dumb-init -- /entrypoint scheduler "$@"
    ;;

  dag-processor)
    wait_for_migrations
    start_healthz "airflow jobs check --job-type DagProcessorJob --hostname $(hostname)"
    exec /usr/bin/dumb-init -- /entrypoint dag-processor "$@"
    ;;

  triggerer)
    wait_for_migrations
    start_ipv6_relay "${AIRFLOW__LOGGING__TRIGGER_LOG_SERVER_PORT:-8794}"
    start_healthz "airflow jobs check --job-type TriggererJob --hostname $(hostname)"
    exec /usr/bin/dumb-init -- /entrypoint triggerer "$@"
    ;;

  worker)
    # A task instance records the host its log server runs on. Railway
    # regenerates the container hostname every deploy, so record the service's
    # stable private domain instead: that is what lets the api-server tail a
    # running task's log.
    export AIRFLOW__CORE__HOSTNAME_CALLABLE="${AIRFLOW__CORE__HOSTNAME_CALLABLE:-railway_airflow.hostname.private_domain}"
    # Celery handles its own warm shutdown; dumb-init must not signal the group.
    export DUMB_INIT_SETSID=0
    wait_for_migrations
    start_ipv6_relay "${AIRFLOW__LOGGING__WORKER_LOG_SERVER_PORT:-8793}"
    start_healthz "celery --app airflow.providers.celery.executors.celery_executor.app inspect ping -d celery@$(hostname)"
    exec /usr/bin/dumb-init -- /entrypoint celery worker "$@"
    ;;

  *)
    log "FATAL: unknown role ${ROLE}"
    exit 64
    ;;
esac
