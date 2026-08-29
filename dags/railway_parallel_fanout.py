"""Fans one task out across a list and folds the results back in.

Dynamic task mapping is what makes a worker tier worth having: the mapped tasks
are queued through Celery and picked up in parallel by however many workers are
running.
"""

from __future__ import annotations

import datetime

from airflow.sdk import dag, task


@dag(
    dag_id="railway_parallel_fanout",
    schedule=None,
    start_date=datetime.datetime(2026, 1, 1),
    catchup=False,
    tags=["example", "mapping"],
    doc_md=__doc__,
)
def railway_parallel_fanout():
    @task
    def make_batches() -> list[int]:
        return list(range(1, 9))

    @task
    def square(value: int) -> int:
        print(f"squaring {value}")
        return value * value

    @task
    def total(values: list[int]) -> int:
        result = sum(values)
        print(f"sum of squares: {result}")
        return result

    total(square.expand(value=make_batches()))


railway_parallel_fanout()
