"""A small end-to-end ETL, written with the TaskFlow API.

Extract, transform and load run as three separate tasks that hand results to
each other over XCom, which is the quickest way to see that the metadata
database, the Celery broker and the worker tier are all doing their jobs.
"""

from __future__ import annotations

import datetime
import random

from airflow.sdk import dag, task

REGIONS = ("north", "south", "east", "west")


@dag(
    dag_id="railway_sales_etl",
    schedule="@daily",
    start_date=datetime.datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["example", "taskflow"],
    doc_md=__doc__,
)
def railway_sales_etl():
    @task
    def extract(**context) -> list[dict[str, object]]:
        """Stand in for a source system with a deterministic day of orders."""
        seed = context["logical_date"].strftime("%Y%m%d") if context.get("logical_date") else "20260101"
        rng = random.Random(seed)
        orders = [
            {
                "id": f"{seed}-{index:03d}",
                "region": rng.choice(REGIONS),
                "amount": round(rng.uniform(10, 500), 2),
            }
            for index in range(rng.randint(40, 120))
        ]
        print(f"extracted {len(orders)} orders")
        return orders

    @task
    def transform(orders: list[dict[str, object]]) -> dict[str, float]:
        """Roll the orders up per region."""
        totals: dict[str, float] = {}
        for order in orders:
            region = str(order["region"])
            totals[region] = round(totals.get(region, 0.0) + float(order["amount"]), 2)
        for region in sorted(totals):
            print(f"{region:>5}: {totals[region]:>10.2f}")
        return totals

    @task
    def load(totals: dict[str, float]) -> str:
        """Where a real pipeline would write to a warehouse."""
        best = max(totals, key=totals.__getitem__)
        summary = f"{len(totals)} regions, {sum(totals.values()):.2f} total, best was {best}"
        print(summary)
        return summary

    load(transform(extract()))


railway_sales_etl()
