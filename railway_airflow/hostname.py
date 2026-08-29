"""Airflow ``[core] hostname_callable`` for Railway.

Railway gives every deployment a fresh container hostname, so the address a task
instance records for its own log server is unusable the moment the container is
replaced. The service's private domain is stable for the life of the service,
which is what lets the api-server reach a running task's log server.

``RAILWAY_PRIVATE_DOMAIN`` is empty on a service's first-ever deployment — and a
template deploys every service for the first time at once — so the service name,
which is always injected, is the fallback rather than the container hostname.
"""

from __future__ import annotations

import os
import socket


def private_domain() -> str:
    domain = os.environ.get("RAILWAY_PRIVATE_DOMAIN")
    if not domain:
        service = os.environ.get("RAILWAY_SERVICE_NAME")
        if service:
            domain = f"{service}.railway.internal"
    return domain or socket.getfqdn()
