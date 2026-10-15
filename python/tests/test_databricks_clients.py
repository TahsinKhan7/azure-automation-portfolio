from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
import requests
import responses

from dataplatform.databricks.adf_monitor import ADFPipelineMonitor
from dataplatform.databricks.clusters import ClusterManager
from dataplatform.databricks.delta_maintenance import (
    DeltaMaintenanceRunner,
    MaintenanceTask,
    build_statements,
    table_reference,
)
from dataplatform.databricks.http import ApiError, HttpClient
from dataplatform.databricks.readers import (
    adls_uri,
    azure_sql_jdbc_url,
    read_delta,
    require_columns,
)
from dataplatform.databricks.token_rotation import TokenRotator
from dataplatform.databricks.unity_catalog import UnityCatalogManager

HOST = "https://adb-0000000000000000.0.azuredatabricks.net"


def make_client(**kwargs) -> HttpClient:
    return HttpClient(HOST, "test-token", sleep=lambda _: None, backoff_seconds=0, **kwargs)


# ------------------------------------------------------------------------------ http
@responses.activate
def test_http_client_sends_bearer_and_decodes_json() -> None:
    responses.get(f"{HOST}/api/2.0/clusters/list", json={"clusters": [{"cluster_id": "a"}]})
    body = make_client().get("/api/2.0/clusters/list")
    assert body == {"clusters": [{"cluster_id": "a"}]}
    assert responses.calls[0].request.headers["Authorization"] == "Bearer test-token"


@responses.activate
def test_http_client_retries_on_429_then_succeeds() -> None:
    url = f"{HOST}/api/2.0/x"
    responses.get(url, status=429, headers={"Retry-After": "1"})
    responses.get(url, status=503)
    responses.get(url, json={"ok": True})
    slept: list[float] = []
    client = HttpClient(HOST, lambda: "tok", sleep=slept.append, backoff_seconds=0.1)
    assert client.get("/api/2.0/x") == {"ok": True}
    assert len(responses.calls) == 3
    assert slept[0] == 1.0  # Retry-After honoured


@responses.activate
def test_http_client_gives_up_after_max_retries() -> None:
    url = f"{HOST}/api/2.0/x"
    for _ in range(3):
        responses.get(url, status=500, json={"message": "boom"})
    with pytest.raises(ApiError) as excinfo:
        make_client(max_retries=2).get("/api/2.0/x")
    assert excinfo.value.status == 500 and "boom" in str(excinfo.value)
    assert len(responses.calls) == 3


@responses.activate
def test_http_client_does_not_retry_client_errors() -> None:
    responses.get(f"{HOST}/api/2.0/x", status=404, json={"error_code": "NOT_FOUND"})
    with pytest.raises(ApiError) as excinfo:
        make_client().get("/api/2.0/x")
    assert excinfo.value.status == 404 and len(responses.calls) == 1


@responses.activate
def test_http_client_retries_connection_errors() -> None:
    url = f"{HOST}/api/2.0/x"
    responses.get(url, body=requests.ConnectionError("reset"))
    responses.get(url, json={})
    assert make_client().get("/api/2.0/x") == {}


# -------------------------------------------------------------------------- clusters
NOW = datetime(2025, 6, 1, 12, 0, tzinfo=timezone.utc)


def _ms(dt: datetime) -> int:
    return int(dt.timestamp() * 1000)


@responses.activate
def test_find_idle_clusters_filters_correctly() -> None:
    responses.get(
        f"{HOST}/api/2.0/clusters/list",
        json={
            "clusters": [
                {
                    "cluster_id": "idle",
                    "cluster_name": "adhoc",
                    "state": "RUNNING",
                    "last_activity_time": _ms(NOW - timedelta(hours=3)),
                    "num_workers": 4,
                },
                {
                    "cluster_id": "busy",
                    "cluster_name": "busy",
                    "state": "RUNNING",
                    "last_activity_time": _ms(NOW - timedelta(minutes=5)),
                },
                {
                    "cluster_id": "job",
                    "cluster_name": "job",
                    "state": "RUNNING",
                    "cluster_source": "JOB",
                    "last_activity_time": _ms(NOW - timedelta(hours=9)),
                },
                {
                    "cluster_id": "off",
                    "cluster_name": "off",
                    "state": "TERMINATED",
                    "last_activity_time": _ms(NOW - timedelta(days=2)),
                },
            ]
        },
    )
    idle = ClusterManager(make_client()).find_idle_clusters(idle_minutes=60, now=NOW)
    assert [c.cluster_id for c in idle] == ["idle"]
    assert idle[0].idle_minutes == 180 and idle[0].num_workers == 4


@responses.activate
def test_terminate_idle_clusters_respects_dry_run() -> None:
    payload = {
        "clusters": [
            {"cluster_id": "c1", "cluster_name": "x", "state": "RUNNING", "last_activity_time": 1}
        ]
    }
    responses.get(f"{HOST}/api/2.0/clusters/list", json=payload)
    responses.get(f"{HOST}/api/2.0/clusters/list", json=payload)
    delete = responses.post(f"{HOST}/api/2.0/clusters/delete", json={})
    manager = ClusterManager(make_client())
    assert len(manager.terminate_idle_clusters(idle_minutes=1, dry_run=True)) == 1
    assert delete.call_count == 0
    manager.terminate_idle_clusters(idle_minutes=1, dry_run=False)
    assert delete.call_count == 1


@responses.activate
def test_cluster_report_and_resize_validation() -> None:
    responses.get(
        f"{HOST}/api/2.0/clusters/list",
        json={
            "clusters": [
                {
                    "cluster_id": "a",
                    "cluster_name": "auto",
                    "state": "RUNNING",
                    "autoscale": {"min_workers": 1, "max_workers": 4},
                }
            ]
        },
    )
    manager = ClusterManager(make_client())
    assert manager.cluster_report()[0]["workers"] == "1-4"
    with pytest.raises(ValueError):
        manager.resize_cluster("a", -1)


# --------------------------------------------------------------------- unity catalog
@responses.activate
def test_setup_medallion_is_idempotent() -> None:
    uc = f"{HOST}/api/2.1/unity-catalog"
    responses.get(
        f"{uc}/catalogs/dataplatform_dev", status=404, json={"error_code": "CATALOG_DOES_NOT_EXIST"}
    )
    create_catalog = responses.post(f"{uc}/catalogs", json={"name": "dataplatform_dev"})
    responses.get(f"{uc}/schemas", json={"schemas": [{"name": "bronze"}]})
    create_schema = responses.post(f"{uc}/schemas", json={})
    grant = responses.patch(f"{uc}/permissions/catalog/dataplatform_dev", json={})

    outcome = UnityCatalogManager(make_client()).setup_medallion(
        "dataplatform_dev", schemas=("bronze", "silver", "gold")
    )
    assert outcome["catalog_created"] is True
    assert outcome["schemas_created"] == ["silver", "gold"]
    assert (
        create_catalog.call_count == 1 and create_schema.call_count == 2 and grant.call_count == 3
    )


@responses.activate
def test_audit_catalog_structure() -> None:
    uc = f"{HOST}/api/2.1/unity-catalog"
    responses.get(f"{uc}/schemas", json={"schemas": [{"name": "silver"}, {"name": "__internal"}]})
    responses.get(
        f"{uc}/tables",
        json={
            "tables": [{"name": "claims", "table_type": "MANAGED", "data_source_format": "DELTA"}]
        },
    )
    responses.get(
        f"{uc}/permissions/catalog/cat",
        json={"privilege_assignments": [{"principal": "p", "privileges": ["SELECT"]}]},
    )
    audit = UnityCatalogManager(make_client()).audit_catalog("cat")
    assert [s["name"] for s in audit["schemas"]] == ["silver"]
    assert audit["schemas"][0]["tables"][0]["format"] == "DELTA"
    assert audit["permissions"][0]["principal"] == "p"


@responses.activate
def test_catalog_exists_propagates_non_404_errors() -> None:
    responses.get(
        f"{HOST}/api/2.1/unity-catalog/catalogs/x", status=403, json={"message": "denied"}
    )
    with pytest.raises(ApiError):
        UnityCatalogManager(make_client()).catalog_exists("x")


# -------------------------------------------------------------------------------- adf
class FakeCredential:
    def get_token(self, *scopes, **kwargs):
        return SimpleNamespace(token="arm-token", expires_on=0)


def _monitor() -> ADFPipelineMonitor:
    client = HttpClient(
        "https://management.azure.com", "arm-token", sleep=lambda _: None, backoff_seconds=0
    )
    return ADFPipelineMonitor(
        "00000000-0000-0000-0000-000000000000",
        "rg-dataplatform-dev",
        "adf-dataplatform-dev",
        FakeCredential(),
        client=client,
    )


@responses.activate
def test_adf_summary_follows_continuation_tokens() -> None:
    url = (
        "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/"
        "rg-dataplatform-dev/providers/Microsoft.DataFactory/factories/adf-dataplatform-dev/queryPipelineRuns"
    )
    responses.post(
        url,
        json={
            "value": [{"status": "Succeeded"}, {"status": "Failed", "pipelineName": "pl_claims"}],
            "continuationToken": "t1",
        },
    )
    responses.post(url, json={"value": [{"status": "Succeeded"}, {"status": "InProgress"}]})
    summary = _monitor().summarise(hours=24)
    assert (summary.total, summary.succeeded, summary.failed, summary.in_progress) == (4, 2, 1, 1)
    assert summary.success_rate == 50.0
    assert len(responses.calls) == 2
    assert (
        responses.calls[1].request.body and b"continuationToken" in responses.calls[1].request.body
    )


@responses.activate
def test_adf_long_running_detection() -> None:
    url = (
        "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/"
        "rg-dataplatform-dev/providers/Microsoft.DataFactory/factories/adf-dataplatform-dev/queryPipelineRuns"
    )
    responses.post(
        url,
        json={
            "value": [
                {
                    "status": "InProgress",
                    "pipelineName": "slow",
                    "runId": "r1",
                    "runStart": (NOW - timedelta(hours=3)).isoformat(),
                },
                {
                    "status": "InProgress",
                    "pipelineName": "quick",
                    "runId": "r2",
                    "runStart": (NOW - timedelta(minutes=10)).isoformat(),
                },
            ]
        },
    )
    long = _monitor().long_running(threshold_minutes=120, now=NOW)
    assert [lr.pipeline_name for lr in long] == ["slow"] and long[0].duration_minutes == 180


def test_adf_default_client_uses_credential_token() -> None:
    monitor = ADFPipelineMonitor("sub", "rg", "adf", FakeCredential())
    assert monitor.client._headers()["Authorization"] == "Bearer arm-token"


# ------------------------------------------------------------------------------ readers
def test_reader_helpers() -> None:
    assert (
        adls_uri("stdataplatformdev", "bronze", "/claims/")
        == "abfss://bronze@stdataplatformdev.dfs.core.windows.net/claims/"
    )
    assert azure_sql_jdbc_url("sql-dataplatform-dev", "ops").startswith(
        "jdbc:sqlserver://sql-dataplatform-dev.database.windows.net:1433;database=ops;encrypt=true"
    )
    with pytest.raises(ValueError):
        read_delta(MagicMock(), "/p", version=1, timestamp="2025-01-01")


@pytest.mark.spark
def test_require_columns(customers_df) -> None:
    assert require_columns(customers_df, ["customer_id"]) is customers_df
    with pytest.raises(ValueError, match="ghost"):
        require_columns(customers_df, ["ghost"])


# --------------------------------------------------------------------- token rotation
def _token(token_id: str, comment: str, expiry_ms: int = -1):
    return SimpleNamespace(token_id=token_id, comment=comment, expiry_time=expiry_ms)


def test_rotate_creates_stores_and_revokes_previous() -> None:
    w = MagicMock()
    w.tokens.list.return_value = [
        _token("old-1", "dataplatform-rotated:adb-pat"),
        _token("other", "manual"),
    ]
    w.tokens.create.return_value = SimpleNamespace(
        token_info=SimpleNamespace(token_id="new-1"), token_value="dapi-secret"
    )
    kv = MagicMock()

    result = TokenRotator(w, kv).rotate("adb-pat", lifetime_days=7, now=NOW)

    w.tokens.create.assert_called_once_with(
        comment="dataplatform-rotated:adb-pat", lifetime_seconds=7 * 86_400
    )
    kv.set_secret.assert_called_once()
    assert kv.set_secret.call_args.args == ("adb-pat", "dapi-secret")
    assert kv.set_secret.call_args.kwargs["expires_on"] == NOW + timedelta(days=7)
    w.tokens.delete.assert_called_once_with(token_id="old-1")
    assert result.new_token_id == "new-1" and result.revoked_token_ids == ("old-1",)
    assert "dapi-secret" not in repr(result)


def test_rotate_revokes_new_token_if_key_vault_write_fails() -> None:
    w = MagicMock()
    w.tokens.list.return_value = []
    w.tokens.create.return_value = SimpleNamespace(
        token_info=SimpleNamespace(token_id="new-1"), token_value="x"
    )
    kv = MagicMock()
    kv.set_secret.side_effect = RuntimeError("kv down")
    with pytest.raises(RuntimeError, match="kv down"):
        TokenRotator(w, kv).rotate("adb-pat")
    w.tokens.delete.assert_called_once_with(token_id="new-1")


def test_tokens_expiring_within() -> None:
    w = MagicMock()
    soon = int((NOW + timedelta(days=2)).timestamp() * 1000)
    later = int((NOW + timedelta(days=40)).timestamp() * 1000)
    w.tokens.list.return_value = [
        _token("a", "dataplatform-rotated:x", soon),
        _token("b", "dataplatform-rotated:y", later),
        _token("c", "manual", soon),
        _token("d", "dataplatform-rotated:z", -1),
    ]
    expiring = TokenRotator(w, MagicMock()).tokens_expiring_within(7, now=NOW)
    assert [t.token_id for t in expiring] == ["a"]
    with pytest.raises(ValueError):
        TokenRotator(w, MagicMock()).rotate("x", lifetime_days=0)


# ------------------------------------------------------------------ delta maintenance
def test_table_reference_and_statements() -> None:
    assert table_reference("dataplatform_dev.silver.claims") == "dataplatform_dev.silver.claims"
    assert (
        table_reference("abfss://silver@acct.dfs.core.windows.net/claims/")
        == "delta.`abfss://silver@acct.dfs.core.windows.net/claims/`"
    )
    with pytest.raises(ValueError):
        table_reference("not valid!")
    task = MaintenanceTask(
        "cat.silver.claims",
        zorder_by=("claim_date", "policy_number"),
        vacuum_retention_hours=168,
        optimize_where="year = 2025",
    )
    assert build_statements(task) == [
        "OPTIMIZE cat.silver.claims WHERE year = 2025 ZORDER BY (claim_date, policy_number)",
        "VACUUM cat.silver.claims RETAIN 168 HOURS",
    ]
    assert build_statements(MaintenanceTask("cat.s.t", vacuum_retention_hours=None)) == [
        "OPTIMIZE cat.s.t"
    ]


def test_runner_enforces_allow_list_and_retention() -> None:
    runner = DeltaMaintenanceRunner(MagicMock(), allow_list=["cat.silver.claims"], dry_run=True)
    outcomes = runner.run(
        [
            MaintenanceTask("cat.silver.claims"),
            MaintenanceTask("cat.silver.secret"),
            MaintenanceTask("cat.silver.claims", vacuum_retention_hours=1),
        ]
    )
    assert outcomes[0].statements and outcomes[0].error is None and outcomes[0].executed is False
    assert "allow-list" in outcomes[1].error
    assert "safety threshold" in outcomes[2].error
    runner.spark.sql.assert_not_called()


@pytest.mark.spark
def test_runner_executes_optimize_on_local_delta(spark, customers_df, delta_path) -> None:
    customers_df.write.format("delta").save(delta_path)
    runner = DeltaMaintenanceRunner(
        spark, allow_list=[delta_path], dry_run=False, allow_short_retention=True
    )
    outcome = runner.run_task(
        MaintenanceTask(delta_path, zorder_by=("customer_id",), vacuum_retention_hours=0)
    )
    assert outcome.executed and outcome.error is None
    assert runner.table_detail(delta_path)["numFiles"] >= 1
    assert spark.read.format("delta").load(delta_path).count() == 3
