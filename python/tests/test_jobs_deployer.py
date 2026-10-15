from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from dataplatform.config.settings import load_settings
from dataplatform.databricks.jobs_deployer import (
    DeployResult,
    JobsDeployer,
    load_job_definitions,
    render_placeholders,
)


def test_load_shipped_job_definitions(config_dir: Path) -> None:
    jobs = load_job_definitions(config_dir / "jobs" / "medallion_pipeline.yml")
    assert [j["name"] for j in jobs] == [
        "dataplatform-{environment}-medallion-claims",
        "dataplatform-{environment}-delta-maintenance",
    ]
    tasks = {t["task_key"]: t for t in jobs[0]["tasks"]}
    assert tasks["silver_to_gold"]["depends_on"] == [{"task_key": "data_quality_gate"}]


def test_load_rejects_incomplete_definition(tmp_path: Path) -> None:
    bad = tmp_path / "bad.yml"
    bad.write_text("jobs:\n  - name: x\n")
    with pytest.raises(ValueError, match="'name' and 'tasks'"):
        load_job_definitions(bad)


def test_render_placeholders_coerces_numeric_fields() -> None:
    rendered = render_placeholders(
        {
            "name": "job-{environment}",
            "autoscale": {"min_workers": "{min_workers}", "max_workers": "{max_workers}"},
            "tags": ["{environment}"],
        },
        {"environment": "dev", "min_workers": "1", "max_workers": "4"},
    )
    assert rendered == {
        "name": "job-dev",
        "autoscale": {"min_workers": 1, "max_workers": 4},
        "tags": ["dev"],
    }


def test_render_placeholders_missing_value_raises() -> None:
    with pytest.raises(KeyError, match="nope"):
        render_placeholders({"a": "{nope}"}, {})


def _job(job_id: int, name: str):
    return SimpleNamespace(job_id=job_id, settings=SimpleNamespace(name=name))


def _definition(name: str = "dataplatform-dev-demo") -> dict:
    return {
        "name": name,
        "tasks": [{"task_key": "t1", "notebook_task": {"notebook_path": "/Shared/x"}}],
        "max_concurrent_runs": 1,
    }


def test_deploy_creates_when_missing() -> None:
    w = MagicMock()
    w.jobs.list.return_value = []
    w.jobs.create.return_value = SimpleNamespace(job_id=42)
    result = JobsDeployer(w).deploy(_definition())
    assert result == DeployResult("dataplatform-dev-demo", 42, "created") and result.changed
    kwargs = w.jobs.create.call_args.kwargs
    assert kwargs["name"] == "dataplatform-dev-demo" and kwargs["tasks"][0]["task_key"] == "t1"
    w.jobs.reset.assert_not_called()


def test_deploy_resets_existing_job_by_name() -> None:
    w = MagicMock()
    w.jobs.list.return_value = [
        _job(7, "dataplatform-dev-demo"),
        _job(8, "dataplatform-dev-demo-other"),
    ]
    result = JobsDeployer(w).deploy(_definition())
    assert result.action == "updated" and result.job_id == 7
    w.jobs.reset.assert_called_once()
    assert w.jobs.reset.call_args.kwargs["job_id"] == 7
    assert w.jobs.reset.call_args.kwargs["new_settings"].name == "dataplatform-dev-demo"


def test_deploy_dry_run_mutates_nothing() -> None:
    w = MagicMock()
    w.jobs.list.side_effect = [[], [_job(1, "dataplatform-dev-demo")]]
    deployer = JobsDeployer(w, dry_run=True)
    assert deployer.deploy(_definition()).action == "planned-create"
    assert deployer.deploy(_definition()).action == "planned-update"
    w.jobs.create.assert_not_called()
    w.jobs.reset.assert_not_called()


def test_duplicate_job_names_are_refused() -> None:
    w = MagicMock()
    w.jobs.list.return_value = [_job(1, "dup"), _job(2, "dup")]
    with pytest.raises(RuntimeError, match="Multiple jobs"):
        JobsDeployer(w).deploy(_definition("dup"))


def test_deploy_file_renders_from_settings(config_dir: Path) -> None:
    settings = load_settings("iqe", config_dir)
    w = MagicMock()
    w.jobs.list.return_value = []
    w.jobs.create.return_value = SimpleNamespace(job_id=1)
    results = JobsDeployer(w).deploy_file(
        config_dir / "jobs" / "medallion_pipeline.yml", settings.placeholders()
    )
    assert [r.job_name for r in results] == [
        "dataplatform-iqe-medallion-claims",
        "dataplatform-iqe-delta-maintenance",
    ]
    cluster = w.jobs.create.call_args_list[0].kwargs["job_clusters"][0]["new_cluster"]
    assert cluster["autoscale"] == {"min_workers": 2, "max_workers": 4}
    assert cluster["spark_version"] == settings.job.spark_version
