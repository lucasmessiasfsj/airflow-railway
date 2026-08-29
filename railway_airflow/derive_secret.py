"""Derive one of Airflow's matched secrets from a single operator-supplied seed.

    python derive_secret.py <seed> <purpose>

Prints 32 bytes as url-safe base64 with padding, which is simultaneously a valid
``cryptography.fernet`` key and a perfectly good JWT / session secret. The same
seed and purpose always produce the same value, so every Airflow service derives
an identical one without any of them writing another service's environment.
"""

from __future__ import annotations

import base64
import hashlib
import sys


def derive(seed: str, purpose: str) -> str:
    digest = hashlib.sha256(f"{seed}:{purpose}".encode()).digest()
    return base64.urlsafe_b64encode(digest).decode()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: derive_secret.py <seed> <purpose>")
    print(derive(sys.argv[1], sys.argv[2]))
