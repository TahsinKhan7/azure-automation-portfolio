"""Azure Data Factory run monitoring through the Azure Resource Manager REST API.

Authenticates with any ``azure.identity`` credential (``DefaultAzureCredential`` in practice)
and queries pipeline runs for failure rates, failed pipelines and long runners. Using ARM
directly keeps the dependency footprint small and the client fully testable with mocked
HTTP responses.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Protocol

from dataplatform.databricks.http import HttpClient

logger = logging.getLogger(__name__)

ARM_BASE_URL = "https://management.azure.com"
ARM_SCOPE = "https://management.azure.com/.default"
API_VERSION = "2018-06-01"


class TokenCredential(Protocol):
    def get_token(self, *scopes: str, **kwargs: Any) -> Any:
        """Return an access token for the requested scopes."""


@dataclass(frozen=True)
class RunSummary:
    total: int
    succeeded: int
    failed: int
    in_progress: int
    cancelled: int

    @property
    def success_rate(self) -> float:
        return round(self.succeeded / self.total * 100, 1) if self.total else 0.0


@dataclass(frozen=True)
class LongRunningPipeline:
    pipeline_name: str
    run_id: str
    duration_minutes: int
    started_at: str


class ADFPipelineMonitor:
    """Query pipeline runs for one Data Factory."""

    def __init__(
        self,
        subscription_id: str,
        resource_group: str,
        factory_name: str,
        credential: TokenCredential,
        client: HttpClient | None = None,
    ):
        self.factory_path = (
            f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}"
            f"/providers/Microsoft.DataFactory/factories/{factory_name}"
        )
        self.factory_name = factory_name
        self.client = client or HttpClient(
            ARM_BASE_URL, lambda: credential.get_token(ARM_SCOPE).token
        )

    def query_runs(self, hours: int = 24, now: datetime | None = None) -> list[dict[str, Any]]:
        """Return pipeline runs updated in the last ``hours`` (follows continuation tokens)."""
        now = now or datetime.now(timezone.utc)
        body: dict[str, Any] = {
            "lastUpdatedAfter": (now - timedelta(hours=hours)).isoformat(),
            "lastUpdatedBefore": now.isoformat(),
        }
        runs: list[dict[str, Any]] = []
        while True:
            page = self.client.post(
                f"{self.factory_path}/queryPipelineRuns?api-version={API_VERSION}", json=body
            )
            runs.extend(page.get("value", []))
            token = page.get("continuationToken")
            if not token:
                return runs
            body["continuationToken"] = token

    def failed_runs(self, hours: int = 24) -> list[dict[str, Any]]:
        return [r for r in self.query_runs(hours) if r.get("status") == "Failed"]

    def summarise(self, hours: int = 24) -> RunSummary:
        runs = self.query_runs(hours)
        by_status = {
            status: sum(1 for r in runs if r.get("status") == status)
            for status in ("Succeeded", "Failed", "InProgress", "Cancelled")
        }
        return RunSummary(
            total=len(runs),
            succeeded=by_status["Succeeded"],
            failed=by_status["Failed"],
            in_progress=by_status["InProgress"],
            cancelled=by_status["Cancelled"],
        )

    def long_running(
        self, threshold_minutes: int = 120, now: datetime | None = None
    ) -> list[LongRunningPipeline]:
        now = now or datetime.now(timezone.utc)
        result = []
        for run in self.query_runs(24, now=now):
            if run.get("status") != "InProgress" or not run.get("runStart"):
                continue
            started = _parse_iso(run["runStart"])
            minutes = int((now - started).total_seconds() // 60)
            if minutes > threshold_minutes:
                result.append(
                    LongRunningPipeline(
                        run.get("pipelineName", ""), run.get("runId", ""), minutes, run["runStart"]
                    )
                )
        return result

    def report(self, hours: int = 24) -> dict[str, Any]:
        """Structured report suitable for logging or posting to a webhook."""
        summary = self.summarise(hours)
        failed = self.failed_runs(hours)
        report = {
            "factory": self.factory_name,
            "window_hours": hours,
            "summary": {**summary.__dict__, "success_rate": summary.success_rate},
            "failed": [
                {
                    "pipeline": r.get("pipelineName"),
                    "run_id": r.get("runId"),
                    "message": r.get("message"),
                }
                for r in failed[:20]
            ],
            "long_running": [lr.__dict__ for lr in self.long_running()],
        }
        logger.info(
            "ADF %s: %d runs, %.1f%% success, %d failed",
            self.factory_name,
            summary.total,
            summary.success_rate,
            summary.failed,
        )
        return report


def _parse_iso(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
