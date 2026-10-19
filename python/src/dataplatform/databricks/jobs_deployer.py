"""Deploy Databricks Jobs (Jobs API 2.1) from YAML, idempotently, using the Databricks SDK.

Job definitions live in ``config/jobs/*.yml`` with ``{placeholder}`` tokens that are filled
from the environment settings (cluster sizes, Spark version, environment name). Deployment
is create-or-update keyed on the job name, so the same file can be applied repeatedly and
promoted through dev -> ite -> iqe -> preprod -> prod without manual edits.
"""

from __future__ import annotations

import logging
import os
import re
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

logger = logging.getLogger(__name__)

_PLACEHOLDER = re.compile(r"^\{([a-zA-Z0-9_]+)\}$")
_INLINE_PLACEHOLDER = re.compile(r"\{([a-zA-Z0-9_]+)\}")
_INT_FIELDS = frozenset(
    {"min_workers", "max_workers", "num_workers", "max_retries", "timeout_seconds"}
)


@dataclass(frozen=True)
class DeployResult:
    job_name: str
    job_id: int | None
    action: str  # created | updated | unchanged | planned-create | planned-update

    @property
    def changed(self) -> bool:
        return self.action in {"created", "updated"}


def load_job_definitions(path: str | os.PathLike[str]) -> list[dict[str, Any]]:
    """Read a YAML file containing ``jobs: [...]`` (or a single job mapping)."""
    file = Path(path)
    with file.open("r", encoding="utf-8") as handle:
        raw = yaml.safe_load(handle) or {}
    jobs = raw.get("jobs") if isinstance(raw, dict) and "jobs" in raw else [raw]
    if not isinstance(jobs, list) or not jobs:
        raise ValueError(f"No job definitions found in {file}")
    for job in jobs:
        if "name" not in job or "tasks" not in job:
            raise ValueError(f"Each job needs 'name' and 'tasks' ({file})")
    return jobs


def render_placeholders(node: Any, values: Mapping[str, str], key: str | None = None) -> Any:
    """Recursively substitute ``{placeholder}`` tokens, coercing known numeric fields to int."""
    if isinstance(node, dict):
        return {k: render_placeholders(v, values, k) for k, v in node.items()}
    if isinstance(node, list):
        return [render_placeholders(item, values, key) for item in node]
    if isinstance(node, str):
        whole = _PLACEHOLDER.match(node)
        if whole:
            name = whole.group(1)
            if name not in values:
                raise KeyError(f"No value for placeholder '{name}'")
            rendered: Any = values[name]
        else:

            def _sub(match: re.Match[str]) -> str:
                name = match.group(1)
                if name not in values:
                    raise KeyError(f"No value for placeholder '{name}'")
                return str(values[name])

            rendered = _INLINE_PLACEHOLDER.sub(_sub, node)
        if key in _INT_FIELDS and isinstance(rendered, str) and rendered.isdigit():
            return int(rendered)
        return rendered
    return node


class JobsDeployer:
    """Create-or-update Databricks jobs by name.

    Args:
        workspace_client: A ``databricks.sdk.WorkspaceClient`` (or compatible object).
        dry_run: Plan only; log what would change and make no API calls that mutate state.
    """

    def __init__(self, workspace_client: Any, dry_run: bool = False):
        self.w = workspace_client
        self.dry_run = dry_run

    def find_job_id(self, name: str) -> int | None:
        matches = [
            job
            for job in self.w.jobs.list(name=name)
            if getattr(job, "settings", None) and job.settings.name == name
        ]
        if len(matches) > 1:
            raise RuntimeError(
                f"Multiple jobs named '{name}' exist; names must be unique for idempotent deploys"
            )
        return matches[0].job_id if matches else None

    def deploy(self, definition: Mapping[str, Any]) -> DeployResult:
        """Create or reset one job from a rendered definition."""
        from databricks.sdk.service.jobs import JobSettings

        name = definition["name"]
        settings = JobSettings.from_dict(dict(definition))
        job_id = self.find_job_id(name)

        if job_id is None:
            if self.dry_run:
                logger.info("[dry-run] would create job '%s'", name)
                return DeployResult(name, None, "planned-create")
            created = self.w.jobs.create(**settings.as_dict())
            logger.info("Created job '%s' (id=%s)", name, created.job_id)
            return DeployResult(name, created.job_id, "created")

        if self.dry_run:
            logger.info("[dry-run] would update job '%s' (id=%s)", name, job_id)
            return DeployResult(name, job_id, "planned-update")
        self.w.jobs.reset(job_id=job_id, new_settings=settings)
        logger.info("Updated job '%s' (id=%s)", name, job_id)
        return DeployResult(name, job_id, "updated")

    def deploy_file(
        self, path: str | os.PathLike[str], placeholders: Mapping[str, str]
    ) -> list[DeployResult]:
        """Render and deploy every job in a YAML file."""
        results = []
        for definition in load_job_definitions(path):
            rendered = render_placeholders(definition, placeholders)
            results.append(self.deploy(rendered))
        changed = sum(1 for r in results if r.changed)
        logger.info(
            "Deployed %d job definition(s) from %s (%d changed)", len(results), path, changed
        )
        return results
