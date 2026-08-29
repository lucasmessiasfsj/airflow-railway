"""A Railway health endpoint for the Airflow roles that serve no HTTP.

Railway decides a deployment is live by probing ``$PORT``. The scheduler and the
api-server answer for themselves; the dag-processor, triggerer and celery worker
do not, and without a probe a crash-looping one of them reports SUCCESS forever.
This serves ``/healthz`` on ``$HEALTHZ_PORT`` and answers it by running the
role's own CLI liveness command, so the check tests the job's heartbeat in the
metadata database rather than merely that a container exists.
"""

from __future__ import annotations

import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

COMMAND = os.environ["HEALTHZ_COMMAND"]
PORT = int(os.environ.get("HEALTHZ_PORT", "8081"))
TIMEOUT = int(os.environ.get("HEALTHZ_TIMEOUT", "30"))
CACHE_SECONDS = int(os.environ.get("HEALTHZ_CACHE_SECONDS", "10"))

_lock = threading.Lock()
_cache = {"at": 0.0, "ok": False, "detail": "not probed yet"}


def probe() -> tuple[bool, str]:
    with _lock:
        if _cache["at"] and time.monotonic() - _cache["at"] < CACHE_SECONDS:
            return _cache["ok"], _cache["detail"]
        try:
            finished = subprocess.run(
                ["/bin/bash", "-c", COMMAND],
                capture_output=True,
                text=True,
                timeout=TIMEOUT,
            )
            ok = finished.returncode == 0
            detail = (finished.stdout + finished.stderr).strip()[-500:]
        except subprocess.TimeoutExpired:
            ok, detail = False, f"liveness command timed out after {TIMEOUT}s"
        _cache.update(at=time.monotonic(), ok=ok, detail=detail)
        return ok, detail


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:  # noqa: N802 - http.server's spelling
        if self.path.split("?", 1)[0] not in ("/healthz", "/"):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        ok, detail = probe()
        body = ("healthy\n" if ok else "unhealthy\n").encode() + detail.encode() + b"\n"
        self.send_response(200 if ok else 503)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args) -> None:
        """Keep the probe out of the deploy log."""


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
