"""Proves the triggerer is doing its job.

A deferrable sensor hands its wait to the triggerer instead of holding a worker
slot for the duration, so a run of this DAG shows a task in the ``deferred``
state and a triggerer picking it back up.
"""

from __future__ import annotations

import datetime

from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.sensors.time_delta import TimeDeltaSensor
from airflow.sdk import DAG

with DAG(
    dag_id="railway_deferrable_wait",
    schedule="@hourly",
    start_date=datetime.datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["example", "triggerer"],
    doc_md=__doc__,
) as dag:
    wait = TimeDeltaSensor(
        task_id="wait_ninety_seconds",
        delta=datetime.timedelta(seconds=90),
        deferrable=True,
    )
    report = BashOperator(
        task_id="report",
        bash_command='echo "the triggerer resumed this task at $(date -u +%FT%TZ)"',
    )

    wait >> report
