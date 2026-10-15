"""Cluster lifecycle and cost hygiene via the Clusters API.

Typical use is a scheduled job that reports on running clusters and terminates those idle
beyond a threshold, with ``dry_run=True`` as the default so nothing is stopped by accident.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from dataplatform.databricks.http import HttpClient

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class IdleCluster:
    cluster_id: str
    cluster_name: str
    idle_minutes: int
    num_workers: int
    creator: str


class ClusterManager:
    """Thin wrapper over ``/api/2.0/clusters``."""

    def __init__(self, client: HttpClient):
        self.client = client

    def list_clusters(self) -> list[dict[str, Any]]:
        return list(self.client.get("/api/2.0/clusters/list").get("clusters", []))

    def get_cluster(self, cluster_id: str) -> dict[str, Any]:
        return self.client.get("/api/2.0/clusters/get", params={"cluster_id": cluster_id})

    def start_cluster(self, cluster_id: str) -> None:
        self.client.post("/api/2.0/clusters/start", json={"cluster_id": cluster_id})
        logger.info("Started cluster %s", cluster_id)

    def terminate_cluster(self, cluster_id: str) -> None:
        self.client.post("/api/2.0/clusters/delete", json={"cluster_id": cluster_id})
        logger.info("Terminated cluster %s", cluster_id)

    def resize_cluster(self, cluster_id: str, num_workers: int) -> None:
        if num_workers < 0:
            raise ValueError("num_workers must be >= 0")
        self.client.post(
            "/api/2.0/clusters/resize", json={"cluster_id": cluster_id, "num_workers": num_workers}
        )
        logger.info("Resized cluster %s to %d workers", cluster_id, num_workers)

    def find_idle_clusters(
        self, idle_minutes: int = 60, now: datetime | None = None, exclude_job_clusters: bool = True
    ) -> list[IdleCluster]:
        """Return RUNNING all-purpose clusters with no activity for ``idle_minutes``."""
        now = now or datetime.now(timezone.utc)
        threshold = timedelta(minutes=idle_minutes)
        idle: list[IdleCluster] = []
        for cluster in self.list_clusters():
            if cluster.get("state") != "RUNNING":
                continue
            if exclude_job_clusters and cluster.get("cluster_source") == "JOB":
                continue
            last_activity_ms = (
                cluster.get("last_activity_time") or cluster.get("last_state_loss_time") or 0
            )
            if not last_activity_ms:
                continue
            last_activity = datetime.fromtimestamp(last_activity_ms / 1000, tz=timezone.utc)
            idle_for = now - last_activity
            if idle_for > threshold:
                workers = cluster.get("num_workers") or cluster.get("autoscale", {}).get(
                    "min_workers", 0
                )
                idle.append(
                    IdleCluster(
                        cluster_id=cluster["cluster_id"],
                        cluster_name=cluster.get("cluster_name", ""),
                        idle_minutes=int(idle_for.total_seconds() // 60),
                        num_workers=int(workers),
                        creator=cluster.get("creator_user_name", ""),
                    )
                )
        return idle

    def terminate_idle_clusters(
        self, idle_minutes: int = 60, dry_run: bool = True
    ) -> list[IdleCluster]:
        """Terminate idle clusters (or only report them when ``dry_run``).

        Returns the clusters affected.
        """
        idle = self.find_idle_clusters(idle_minutes)
        for cluster in idle:
            logger.info(
                "%s idle cluster %s (%s) idle for %dm",
                "Would terminate" if dry_run else "Terminating",
                cluster.cluster_name,
                cluster.cluster_id,
                cluster.idle_minutes,
            )
            if not dry_run:
                self.terminate_cluster(cluster.cluster_id)
        return idle

    def cluster_report(self) -> list[dict[str, Any]]:
        """Compact per-cluster summary for logging or a dashboard table."""
        report = []
        for c in self.list_clusters():
            workers = c.get("num_workers")
            if workers is None and "autoscale" in c:
                workers = f"{c['autoscale'].get('min_workers')}-{c['autoscale'].get('max_workers')}"
            report.append(
                {
                    "cluster_id": c.get("cluster_id"),
                    "cluster_name": c.get("cluster_name"),
                    "state": c.get("state"),
                    "workers": workers,
                    "spark_version": c.get("spark_version"),
                    "node_type_id": c.get("node_type_id"),
                    "source": c.get("cluster_source"),
                }
            )
        return report
