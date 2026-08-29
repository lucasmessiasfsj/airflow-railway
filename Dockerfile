# Apache Airflow 3 on Railway.
#
# The published image already contains every component (api-server, scheduler,
# dag-processor, triggerer, celery worker); the roles differ only by start
# command. This layer adds what Railway needs on top of it:
#
#   * a boot-time entrypoint that derives the three matched Airflow secrets from
#     one operator-supplied seed, wires the managed Postgres / Redis / bucket,
#     and runs the metadata migration exactly once (on the api-server),
#   * an IPv6 relay, because Railway's private network routes IPv6 only and
#     uvicorn binds IPv4,
#   * a health endpoint for the roles that serve no HTTP of their own,
#   * the DAGs that ship with the template.
#
# Pinned rather than floating: the five Airflow services must run the same build
# as each other, and the metadata database has an on-disk schema this version
# owns.
FROM apache/airflow:3.3.1

USER root

# socat backs the IPv6 relay in railway-entrypoint.sh.
RUN apt-get update \
 && apt-get install -y --no-install-recommends socat \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY railway-entrypoint.sh /railway-entrypoint.sh
COPY railway_airflow/ /opt/airflow/railway_airflow/
COPY dags/ /opt/airflow/dags/

RUN chmod 0755 /railway-entrypoint.sh \
 && chown -R "50000:0" /opt/airflow/railway_airflow /opt/airflow/dags \
 && bash -n /railway-entrypoint.sh

USER 50000

# /opt/airflow on the path makes railway_airflow importable from
# `[core] hostname_callable`, which Airflow resolves as a dotted import.
ENV PYTHONPATH=/opt/airflow \
    AIRFLOW__CORE__EXECUTOR=CeleryExecutor \
    AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager \
    AIRFLOW__CORE__LOAD_EXAMPLES=False \
    AIRFLOW__API__WORKERS=1 \
    AIRFLOW__CELERY__WORKER_CONCURRENCY=4 \
    FORWARDED_ALLOW_IPS=*

# Fail the build, not a container, on a typo in anything shipped above.
RUN python -m compileall -q /opt/airflow/railway_airflow /opt/airflow/dags
