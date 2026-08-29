"""Render the Airflow connection that points remote task logging at the bucket.

    python s3_conn.py <access key id> <secret access key> <endpoint> <region>

Emits the JSON form of an ``aws`` connection, which Airflow reads straight from
``AIRFLOW_CONN_<ID>``. Path-style addressing is forced: Railway's bucket accepts
it for every server-side call and it is the only style its CORS configuration
answers, so nothing downstream has to care which one it got.
"""

from __future__ import annotations

import json
import sys


def connection(key: str, secret: str, endpoint: str, region: str) -> str:
    extra = {
        "region_name": region or "auto",
        "config_kwargs": {"s3": {"addressing_style": "path"}},
    }
    if endpoint:
        extra["endpoint_url"] = endpoint if "://" in endpoint else f"https://{endpoint}"
    return json.dumps(
        {"conn_type": "aws", "login": key, "password": secret, "extra": extra}
    )


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("usage: s3_conn.py <key> <secret> <endpoint> <region>")
    print(connection(*sys.argv[1:5]))
