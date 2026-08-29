"""Render ``[dag_processor] dag_bundle_config_list`` for Railway.

    python dag_bundles.py <git repo url> <tracking ref> <subdir>

The image always carries the repository's own ``dags/`` directory as the local
bundle. Supplying a git URL adds a second, versioned bundle so a deployer can
change DAGs without rebuilding the image.
"""

from __future__ import annotations

import json
import sys

LOCAL_BUNDLE = {
    "name": "dags-folder",
    "classpath": "airflow.dag_processing.bundles.local.LocalDagBundle",
    "kwargs": {},
}


def bundles(repo_url: str, ref: str, subdir: str) -> str:
    configured = [LOCAL_BUNDLE]
    if repo_url:
        kwargs = {"repo_url": repo_url, "tracking_ref": ref or "main"}
        if subdir:
            kwargs["subdir"] = subdir
        configured.append(
            {
                "name": "dags-git",
                "classpath": "airflow.providers.git.bundles.git.GitDagBundle",
                "kwargs": kwargs,
            }
        )
    return json.dumps(configured)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: dag_bundles.py <repo url> <ref> <subdir>")
    print(bundles(*sys.argv[1:4]))
