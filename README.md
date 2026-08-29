# Apache Airflow on Railway

A production-shaped [Apache Airflow](https://airflow.apache.org/) 3 deployment:
the api-server, scheduler, dag-processor, triggerer and a Celery worker tier
each run as their own Railway service, backed by managed Postgres, managed Redis
and a Railway bucket.

This repository is a thin layer over the official `apache/airflow` image. It
adds only the things a Railway service cannot express on its own.

## What the layer does

| Concern | How it is handled |
|---|---|
| Three secrets that must match across five services | `railway-entrypoint.sh` derives the Fernet key, the task-execution JWT secret and the API secret key from one `AIRFLOW_SECRET_SEED`, so nothing has to be copied between services |
| Task logs | Written to the Railway bucket, because Railway volumes are 1:1 and the shared `logs/` directory upstream's compose file mounts into every container cannot exist |
| Private networking | Railway routes IPv6 between services while uvicorn and Airflow's log servers bind IPv4, so a `socat` relay serves the IPv6 side of the same port |
| Health checks | The scheduler and api-server answer for themselves; the other roles serve `/healthz` from `railway_airflow/healthz.py`, which runs that role's own `airflow jobs check` / `celery inspect ping` |
| Migrations | The api-server runs `airflow db migrate` and creates the first administrator; every other role waits on `airflow db check-migrations`, since Railway has no service ordering |
| Log addressing | `[core] hostname_callable` reports the worker service's private domain instead of the container hostname Railway regenerates every deploy |

## Services

All five run this same image and differ only by their start command:

```
railway-entrypoint.sh api-server        # public, PORT 8080
railway-entrypoint.sh scheduler         # private, PORT 8974
railway-entrypoint.sh dag-processor     # private, PORT 8081
railway-entrypoint.sh triggerer         # private, PORT 8081
railway-entrypoint.sh worker            # private, PORT 8081
```

## Variables

Every Airflow service needs `AIRFLOW_SECRET_SEED`, `DATABASE_URL`, `REDIS_URL`
and the four `AIRFLOW_LOGS_*` bucket values. The api-server additionally takes
`AIRFLOW_ADMIN_USERNAME` and `AIRFLOW_ADMIN_PASSWORD`, which create the first
administrator on its first boot and are ignored once that account exists.

Any `AIRFLOW__SECTION__KEY` variable set on a service overrides the value this
entrypoint would otherwise compute, so nothing here blocks ordinary Airflow
configuration.

## DAGs

`dags/` is baked into the image as the `dags-folder` bundle. Setting
`AIRFLOW_DAGS_GIT_REPO_URL` (with optional `AIRFLOW_DAGS_GIT_REF` and
`AIRFLOW_DAGS_GIT_SUBDIR`) on every Airflow service adds a versioned git bundle
beside it, so DAGs can change without rebuilding the image.
