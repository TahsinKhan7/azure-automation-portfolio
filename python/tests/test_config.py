from __future__ import annotations

from pathlib import Path

import pytest

from dataplatform.config.settings import (
    ENVIRONMENTS,
    ConfigError,
    DatasetConfig,
    find_config_dir,
    load_settings,
)


@pytest.mark.parametrize("env", ENVIRONMENTS)
def test_every_environment_loads(config_dir: Path, env: str) -> None:
    settings = load_settings(env, config_dir, environ={})
    assert settings.environment == env
    assert settings.storage.account_name.startswith("stdataplatform")
    assert settings.catalog == f"dataplatform_{env}"
    assert set(settings.datasets) == {"claims", "policies", "customers"}
    assert settings.is_production == (env == "prod")


def test_prod_is_more_conservative_than_dev(config_dir: Path) -> None:
    dev, prod = (
        load_settings("dev", config_dir, environ={}),
        load_settings("prod", config_dir, environ={}),
    )
    assert prod.job.delta_retention_hours > dev.job.delta_retention_hours
    assert prod.job.use_spot_instances is False and dev.job.use_spot_instances is True
    assert prod.job.max_workers > dev.job.max_workers


def test_unknown_environment_rejected(config_dir: Path) -> None:
    with pytest.raises(ConfigError, match="Unknown environment"):
        load_settings("staging", config_dir, environ={})
    with pytest.raises(ConfigError, match="DATAPLATFORM_ENV"):
        load_settings(None, config_dir, environ={})


def test_environment_from_env_var_and_overrides(config_dir: Path) -> None:
    environ = {
        "DATAPLATFORM_ENV": "ite",
        "DATAPLATFORM_STORAGE_ACCOUNT": "stoverride",
        "DATAPLATFORM_CATALOG": "cat_override",
        "DATAPLATFORM_SHUFFLE_PARTITIONS": "99",
    }
    settings = load_settings(config_dir=config_dir, environ=environ)
    assert settings.environment == "ite"
    assert settings.storage.account_name == "stoverride"
    assert settings.catalog == "cat_override"
    assert settings.job.shuffle_partitions == 99


def test_path_and_table_helpers(config_dir: Path) -> None:
    settings = load_settings("dev", config_dir, environ={})
    assert (
        settings.path("silver", "claims")
        == "abfss://silver@stdataplatformdev.dfs.core.windows.net/claims/"
    )
    assert settings.path("gold", "claims", "monthly_trends").endswith("/claims/monthly_trends/")
    assert settings.table("silver", "claims") == "dataplatform_dev.silver.claims"
    with pytest.raises(ConfigError, match="No container"):
        settings.path("platinum", "claims")


def test_dataset_lookup(config_dir: Path) -> None:
    settings = load_settings("dev", config_dir, environ={})
    claims = settings.dataset("claims")
    assert claims.key_columns == ["claim_id"] and claims.source_format == "csv"
    assert claims.cast_schema["claim_amount"] == "decimal(18,2)"
    assert " " in claims.schema_ddl and "\n" not in claims.schema_ddl
    assert settings.dataset("customers").scd2.tracked_columns == [
        "full_name",
        "email",
        "postcode",
        "segment",
    ]
    assert settings.resolve(claims.quality_suite).is_file()
    with pytest.raises(ConfigError, match="Unknown dataset"):
        settings.dataset("orders")


def test_placeholders_are_strings(config_dir: Path) -> None:
    placeholders = load_settings("preprod", config_dir, environ={}).placeholders()
    assert placeholders["environment"] == "preprod"
    assert all(isinstance(v, str) for v in placeholders.values())


def test_dataset_config_requires_core_keys() -> None:
    with pytest.raises(ConfigError, match="missing required keys"):
        DatasetConfig.from_mapping("x", {"source_format": "csv"})


def test_find_config_dir_resolution(
    config_dir: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    assert find_config_dir(config_dir) == config_dir
    monkeypatch.setenv("DATAPLATFORM_CONFIG_DIR", str(tmp_path))
    assert find_config_dir() == tmp_path
    with pytest.raises(ConfigError, match="Configuration file not found"):
        load_settings("dev", tmp_path, environ={})
