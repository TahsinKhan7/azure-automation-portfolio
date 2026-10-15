"""Typed, per-environment settings.

Settings are loaded from ``config/<env>.yml`` (non-secret platform settings) and
``config/datasets.yml`` (dataset definitions shared across environments). A small set of
environment variables can override values at runtime, which is how CI and ad-hoc runs
point the same code at a different storage account or workspace without editing YAML.

Secrets are never part of these files; they are resolved at runtime from Key Vault or a
Databricks secret scope.
"""

from __future__ import annotations

import logging
import os
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

logger = logging.getLogger(__name__)

ENVIRONMENTS: tuple[str, ...] = ("dev", "ite", "iqe", "preprod", "prod")
"""Promotion path, in order."""

ENV_PREFIX = "DATAPLATFORM_"

_ENV_OVERRIDES: Mapping[str, tuple[str, ...]] = {
    # environment variable suffix -> path within the parsed YAML document
    "STORAGE_ACCOUNT": ("storage", "account_name"),
    "CATALOG": ("catalog",),
    "WORKSPACE_HOST": ("workspace_host",),
    "KEY_VAULT_NAME": ("key_vault_name",),
    "SHUFFLE_PARTITIONS": ("job", "shuffle_partitions"),
}


class ConfigError(ValueError):
    """Raised when configuration is missing or invalid."""


@dataclass(frozen=True)
class StorageSettings:
    """ADLS Gen2 account and the container used for each lakehouse layer."""

    account_name: str
    containers: dict[str, str] = field(default_factory=dict)

    def container(self, layer: str) -> str:
        try:
            return self.containers[layer]
        except KeyError as exc:
            raise ConfigError(f"No container configured for layer '{layer}'") from exc

    def abfss_root(self, layer: str) -> str:
        return f"abfss://{self.container(layer)}@{self.account_name}.dfs.core.windows.net"


@dataclass(frozen=True)
class JobSettings:
    """Runtime knobs for Spark jobs and job clusters."""

    shuffle_partitions: int = 200
    max_retries: int = 1
    timeout_minutes: int = 60
    delta_retention_hours: int = 168
    use_spot_instances: bool = False
    min_workers: int = 1
    max_workers: int = 4
    cluster_policy_name: str | None = None
    spark_version: str = "15.4.x-scala2.12"
    node_type_id: str = "Standard_D4ds_v5"


@dataclass(frozen=True)
class Scd2Settings:
    """SCD Type 2 settings for dimension-style datasets."""

    tracked_columns: list[str]
    effective_from_column: str | None = None


@dataclass(frozen=True)
class DatasetConfig:
    """How a dataset moves through landing -> bronze -> silver -> gold."""

    name: str
    source_format: str
    schema_ddl: str
    key_columns: list[str]
    order_column: str | None = None
    date_column: str | None = None
    value_column: str | None = None
    group_columns: list[str] = field(default_factory=list)
    partition_columns: list[str] = field(default_factory=list)
    cast_schema: dict[str, str] = field(default_factory=dict)
    source_options: dict[str, str] = field(default_factory=dict)
    quality_suite: str | None = None
    scd2: Scd2Settings | None = None

    @classmethod
    def from_mapping(cls, name: str, raw: Mapping[str, Any]) -> DatasetConfig:
        required = ("source_format", "schema_ddl", "key_columns")
        missing = [key for key in required if key not in raw]
        if missing:
            raise ConfigError(f"Dataset '{name}' is missing required keys: {missing}")
        scd2_raw = raw.get("scd2")
        scd2 = (
            Scd2Settings(
                tracked_columns=list(scd2_raw["tracked_columns"]),
                effective_from_column=scd2_raw.get("effective_from_column"),
            )
            if scd2_raw
            else None
        )
        return cls(
            name=name,
            source_format=str(raw["source_format"]).lower(),
            schema_ddl=" ".join(str(raw["schema_ddl"]).split()),
            key_columns=list(raw["key_columns"]),
            order_column=raw.get("order_column"),
            date_column=raw.get("date_column"),
            value_column=raw.get("value_column"),
            group_columns=list(raw.get("group_columns") or []),
            partition_columns=list(raw.get("partition_columns") or []),
            cast_schema={k: str(v) for k, v in (raw.get("cast_schema") or {}).items()},
            source_options={k: str(v) for k, v in (raw.get("source_options") or {}).items()},
            quality_suite=raw.get("quality_suite"),
            scd2=scd2,
        )


@dataclass(frozen=True)
class Settings:
    """Fully resolved settings for one environment."""

    environment: str
    storage: StorageSettings
    catalog: str
    workspace_host: str
    key_vault_name: str
    job: JobSettings = field(default_factory=JobSettings)
    datasets: dict[str, DatasetConfig] = field(default_factory=dict)
    config_dir: Path | None = None

    @property
    def is_production(self) -> bool:
        return self.environment == "prod"

    def path(self, layer: str, dataset: str, *suffix: str) -> str:
        """Return the ``abfss://`` path for a dataset in a lakehouse layer."""
        parts = "/".join(part.strip("/") for part in (dataset, *suffix) if part)
        return f"{self.storage.abfss_root(layer)}/{parts}/"

    def table(self, schema: str, name: str) -> str:
        """Return the fully qualified Unity Catalog table name."""
        return f"{self.catalog}.{schema}.{name}"

    def dataset(self, name: str) -> DatasetConfig:
        try:
            return self.datasets[name]
        except KeyError as exc:
            known = ", ".join(sorted(self.datasets)) or "<none>"
            raise ConfigError(f"Unknown dataset '{name}'. Known datasets: {known}") from exc

    def resolve(self, relative: str) -> Path:
        """Resolve a path (such as a quality suite) relative to the config directory."""
        base = self.config_dir or Path.cwd()
        return (base / relative).resolve()

    def placeholders(self) -> dict[str, str]:
        """Flat mapping used to substitute ``{placeholder}`` tokens in job definitions."""
        return {
            "environment": self.environment,
            "catalog": self.catalog,
            "storage_account": self.storage.account_name,
            "workspace_host": self.workspace_host,
            "key_vault_name": self.key_vault_name,
            "spark_version": self.job.spark_version,
            "node_type_id": self.job.node_type_id,
            "min_workers": str(self.job.min_workers),
            "max_workers": str(self.job.max_workers),
            "shuffle_partitions": str(self.job.shuffle_partitions),
            "max_retries": str(self.job.max_retries),
        }


def find_config_dir(explicit: str | os.PathLike[str] | None = None) -> Path:
    """Locate the configuration directory.

    Resolution order: explicit argument, ``DATAPLATFORM_CONFIG_DIR``, a ``config`` folder
    next to the package source tree (editable installs), then ``./config``.
    """
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    if os.environ.get(f"{ENV_PREFIX}CONFIG_DIR"):
        candidates.append(Path(os.environ[f"{ENV_PREFIX}CONFIG_DIR"]))
    candidates.append(Path(__file__).resolve().parents[3] / "config")
    candidates.append(Path.cwd() / "config")
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    raise ConfigError(
        "Could not locate a configuration directory. Pass config_dir explicitly or set "
        f"{ENV_PREFIX}CONFIG_DIR."
    )


def _read_yaml(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise ConfigError(f"Configuration file not found: {path}")
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ConfigError(f"Expected a mapping at the top level of {path}")
    return data


def _apply_env_overrides(raw: dict[str, Any], environ: Mapping[str, str]) -> dict[str, Any]:
    for suffix, path in _ENV_OVERRIDES.items():
        value = environ.get(f"{ENV_PREFIX}{suffix}")
        if value is None:
            continue
        node = raw
        for key in path[:-1]:
            node = node.setdefault(key, {})
        current = node.get(path[-1])
        node[path[-1]] = type(current)(value) if isinstance(current, int | float) else value
        logger.debug("Override %s%s applied", ENV_PREFIX, suffix)
    return raw


def load_settings(
    environment: str | None = None,
    config_dir: str | os.PathLike[str] | None = None,
    environ: Mapping[str, str] | None = None,
) -> Settings:
    """Load settings for ``environment``.

    Args:
        environment: One of :data:`ENVIRONMENTS`. Falls back to ``DATAPLATFORM_ENV``.
        config_dir: Directory holding ``<env>.yml`` and ``datasets.yml``.
        environ: Environment mapping (injectable for tests); defaults to ``os.environ``.
    """
    environ = os.environ if environ is None else environ
    environment = environment or environ.get(f"{ENV_PREFIX}ENV")
    if not environment:
        raise ConfigError("No environment given and DATAPLATFORM_ENV is not set")
    if environment not in ENVIRONMENTS:
        raise ConfigError(f"Unknown environment '{environment}'. Expected one of {ENVIRONMENTS}")

    directory = find_config_dir(config_dir)
    raw = _apply_env_overrides(_read_yaml(directory / f"{environment}.yml"), environ)

    storage_raw = raw.get("storage") or {}
    if "account_name" not in storage_raw:
        raise ConfigError(f"storage.account_name missing from {environment}.yml")

    datasets_path = directory / "datasets.yml"
    datasets_raw = _read_yaml(datasets_path) if datasets_path.is_file() else {}
    datasets = {name: DatasetConfig.from_mapping(name, spec) for name, spec in datasets_raw.items()}

    settings = Settings(
        environment=environment,
        storage=StorageSettings(
            account_name=str(storage_raw["account_name"]),
            containers={k: str(v) for k, v in (storage_raw.get("containers") or {}).items()},
        ),
        catalog=str(raw.get("catalog", f"dataplatform_{environment}")),
        workspace_host=str(raw.get("workspace_host", "")).rstrip("/"),
        key_vault_name=str(raw.get("key_vault_name", "")),
        job=JobSettings(**(raw.get("job") or {})),
        datasets=datasets,
        config_dir=directory,
    )
    logger.info(
        "Loaded settings for %s (catalog=%s, storage=%s, %d datasets)",
        environment,
        settings.catalog,
        settings.storage.account_name,
        len(datasets),
    )
    return settings
