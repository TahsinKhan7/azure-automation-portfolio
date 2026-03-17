"""
Azure Data Factory Pipeline Monitor
Queries recent pipeline runs, reports failures, long-running jobs
and success rates for alerting and operational dashboards.
"""

from azure.identity import DefaultAzureCredential
from azure.mgmt.datafactory import DataFactoryManagementClient
from datetime import datetime, timedelta, timezone


class ADFPipelineMonitor:

    def __init__(self, subscription_id, resource_group, factory_name):
        credential = DefaultAzureCredential()
        self.client = DataFactoryManagementClient(credential, subscription_id)
        self.rg = resource_group
        self.factory = factory_name

    def get_recent_runs(self, hours=24):
        now = datetime.now(timezone.utc)
        params = {
            "lastUpdatedAfter": (now - timedelta(hours=hours)).isoformat(),
            "lastUpdatedBefore": now.isoformat()
        }
        return self.client.pipeline_runs.query_by_factory(self.rg, self.factory, params).value

    def get_failed_runs(self, hours=24):
        return [r for r in self.get_recent_runs(hours) if r.status == "Failed"]

    def get_success_rate(self, hours=24):
        runs = self.get_recent_runs(hours)
        if not runs:
            return {"total": 0, "succeeded": 0, "failed": 0, "rate": 0.0}
        succeeded = sum(1 for r in runs if r.status == "Succeeded")
        failed = sum(1 for r in runs if r.status == "Failed")
        return {
            "total": len(runs),
            "succeeded": succeeded,
            "failed": failed,
            "in_progress": sum(1 for r in runs if r.status == "InProgress"),
            "rate": round(succeeded / len(runs) * 100, 1)
        }

    def get_long_running(self, threshold_minutes=120):
        long = []
        for run in self.get_recent_runs(24):
            if run.status == "InProgress" and run.run_start:
                duration = datetime.now(timezone.utc) - run.run_start
                if duration.total_seconds() > threshold_minutes * 60:
                    long.append({
                        "pipeline": run.pipeline_name,
                        "run_id": run.run_id,
                        "duration_min": int(duration.total_seconds() / 60),
                        "started": run.run_start.isoformat()
                    })
        return long

    def print_report(self, hours=24):
        stats = self.get_success_rate(hours)
        failed = self.get_failed_runs(hours)
        long_running = self.get_long_running()

        print(f"\n{'='*50}")
        print(f"ADF Report - Last {hours}h | {self.factory}")
        print(f"{'='*50}\n")
        print(f"Total: {stats['total']} | Passed: {stats['succeeded']} | "
              f"Failed: {stats['failed']} | Rate: {stats['rate']}%")

        if failed:
            print(f"\nFailed pipelines:")
            for r in failed[:10]:
                print(f"  {r.pipeline_name} | {r.run_end}")

        if long_running:
            print(f"\nLong-running (>2h):")
            for r in long_running:
                print(f"  {r['pipeline']} | {r['duration_min']}min")


if __name__ == "__main__":
    monitor = ADFPipelineMonitor("your-sub-id", "rg-data-prod", "adf-prod-001")
    monitor.print_report(24)
