"""Airflow ``[core] hostname_callable`` for Railway.

Railway gives every deployment a fresh container hostname, so the value a task
instance records for its own log server is unusable the moment the container is
replaced. The service's private domain is stable for the life of the service,
which is what lets the api-server reach a running task's log server.
"""

from __future__ import annotations

import os
import socket


def private_domain() -> str:
    return os.environ.get("RAILWAY_PRIVATE_DOMAIN") or socket.getfqdn()
