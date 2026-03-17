"""
Databricks Cluster Lifecycle Manager
Manages cluster start/stop/resize operations via the Databricks REST API.
Designed for cost optimisation by terminating idle clusters and right-sizing.
"""

import requests
import os
from datetime import datetime, timedelta


class DatabricksClusterManager:

    def __init__(self, workspace_url, token):
        self.base_url = f"{workspace_url}/api/2.0"
        self.headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    def _get(self, endpoint, params=None):
        r = requests.get(f"{self.base_url}{endpoint}", headers=self.headers, params=params)
        r.raise_for_status()
        return r.json()

    def _post(self, endpoint, payload):
        r = requests.post(f"{self.base_url}{endpoint}", headers=self.headers, json=payload)
        r.raise_for_status()
        return r.json() if r.text else {}

    def list_clusters(self):
        return self._get("/clusters/list").get("clusters", [])

    def get_cluster(self, cluster_id):
        return self._get("/clusters/get", {"cluster_id": cluster_id})

    def start_cluster(self, cluster_id):
        self._post("/clusters/start", {"cluster_id": cluster_id})
        print(f"  Started cluster: {cluster_id}")

    def terminate_cluster(self, cluster_id):
        self._post("/clusters/delete", {"cluster_id": cluster_id})
        print(f"  Terminated cluster: {cluster_id}")

    def resize_cluster(self, cluster_id, num_workers):
        self._post("/clusters/resize", {"cluster_id": cluster_id, "num_workers": num_workers})
        print(f"  Resized {cluster_id} to {num_workers} workers")

    def find_idle_clusters(self, idle_minutes=60):
        idle = []
        for cluster in self.list_clusters():
            if cluster["state"] != "RUNNING":
                continue
            last_activity = cluster.get("last_activity_time", 0)
            if last_activity == 0:
                continue
            last_active = datetime.fromtimestamp(last_activity / 1000)
            idle_duration = datetime.now() - last_active
            if idle_duration > timedelta(minutes=idle_minutes):
                idle.append({
                    "cluster_id": cluster["cluster_id"],
                    "cluster_name": cluster["cluster_name"],
                    "idle_minutes": int(idle_duration.total_seconds() / 60),
                    "num_workers": cluster.get("num_workers", 0),
                    "driver_node_type": cluster.get("driver_node_type_id", "unknown")
                })
        return idle

    def terminate_idle_clusters(self, idle_minutes=60, dry_run=True):
        idle = self.find_idle_clusters(idle_minutes)
        if not idle:
            print("No idle clusters found.")
            return 0
        print(f"Found {len(idle)} idle cluster(s):")
        terminated = 0
        for c in idle:
            print(f"  {c['cluster_name']} - idle {c['idle_minutes']}m ({c['num_workers']} workers)")
            if not dry_run:
                self.terminate_cluster(c["cluster_id"])
                terminated += 1
        if dry_run:
            print("\nDRY RUN - use dry_run=False to terminate.")
        return terminated

    def print_cluster_report(self):
        clusters = self.list_clusters()
        print(f"\n{'='*60}")
        print(f"Cluster Report | {len(clusters)} clusters")
        print(f"{'='*60}\n")
        for c in clusters:
            workers = c.get("num_workers", c.get("autoscale", {}).get("max_workers", "auto"))
            print(f"  [{c['state']:12s}] {c['cluster_name']}")
            print(f"               Workers: {workers} | Runtime: {c.get('spark_version', 'N/A')}")


if __name__ == "__main__":
    manager = DatabricksClusterManager(
        workspace_url=os.environ.get("DATABRICKS_HOST", "https://adb-xxxx.azuredatabricks.net"),
        token=os.environ.get("DATABRICKS_TOKEN", "")
    )
    manager.print_cluster_report()
    print("\n=== Idle Cluster Check ===")
    manager.terminate_idle_clusters(idle_minutes=90, dry_run=True)
