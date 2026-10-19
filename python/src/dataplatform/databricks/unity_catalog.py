"""Unity Catalog administration: catalogs, schemas, table metadata and grants."""

from __future__ import annotations

import logging
from collections.abc import Mapping, Sequence
from typing import Any

from dataplatform.databricks.http import ApiError, HttpClient

logger = logging.getLogger(__name__)

MEDALLION_SCHEMAS: tuple[str, ...] = ("bronze", "silver", "gold", "quarantine")

DEFAULT_PERMISSION_MODEL: Mapping[str, Sequence[str]] = {
    "dataplatform-engineers": ("USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE"),
    "dataplatform-analysts": ("USE_CATALOG", "USE_SCHEMA", "SELECT"),
    "dataplatform-scientists": ("USE_CATALOG", "USE_SCHEMA", "SELECT", "CREATE_TABLE"),
}


class UnityCatalogManager:
    """Wrapper over ``/api/2.1/unity-catalog``."""

    base = "/api/2.1/unity-catalog"

    def __init__(self, client: HttpClient):
        self.client = client

    # Catalogs ------------------------------------------------------------------
    def list_catalogs(self) -> list[dict[str, Any]]:
        return list(self.client.get(f"{self.base}/catalogs").get("catalogs", []))

    def catalog_exists(self, name: str) -> bool:
        try:
            self.client.get(f"{self.base}/catalogs/{name}")
            return True
        except ApiError as exc:
            if exc.status == 404:
                return False
            raise

    def create_catalog(
        self, name: str, comment: str = "", storage_root: str | None = None
    ) -> dict[str, Any]:
        body: dict[str, Any] = {"name": name, "comment": comment}
        if storage_root:
            body["storage_root"] = storage_root
        return self.client.post(f"{self.base}/catalogs", json=body)

    def ensure_catalog(self, name: str, comment: str = "", storage_root: str | None = None) -> bool:
        """Create the catalog if missing. Returns True when it was created."""
        if self.catalog_exists(name):
            logger.info("Catalog %s already exists", name)
            return False
        self.create_catalog(name, comment, storage_root)
        logger.info("Created catalog %s", name)
        return True

    # Schemas -------------------------------------------------------------------
    def list_schemas(self, catalog: str) -> list[dict[str, Any]]:
        return list(
            self.client.get(f"{self.base}/schemas", params={"catalog_name": catalog}).get(
                "schemas", []
            )
        )

    def create_schema(self, catalog: str, schema: str, comment: str = "") -> dict[str, Any]:
        return self.client.post(
            f"{self.base}/schemas",
            json={"name": schema, "catalog_name": catalog, "comment": comment},
        )

    def ensure_schema(self, catalog: str, schema: str, comment: str = "") -> bool:
        existing = {s["name"] for s in self.list_schemas(catalog)}
        if schema in existing:
            return False
        self.create_schema(catalog, schema, comment)
        logger.info("Created schema %s.%s", catalog, schema)
        return True

    # Tables --------------------------------------------------------------------
    def list_tables(self, catalog: str, schema: str) -> list[dict[str, Any]]:
        return list(
            self.client.get(
                f"{self.base}/tables", params={"catalog_name": catalog, "schema_name": schema}
            ).get("tables", [])
        )

    def get_table(self, full_name: str) -> dict[str, Any]:
        return self.client.get(f"{self.base}/tables/{full_name}")

    # Permissions ---------------------------------------------------------------
    def get_permissions(self, securable_type: str, full_name: str) -> list[dict[str, Any]]:
        body = self.client.get(f"{self.base}/permissions/{securable_type}/{full_name}")
        return list(body.get("privilege_assignments", []))

    def grant(
        self, securable_type: str, full_name: str, principal: str, privileges: Sequence[str]
    ) -> dict[str, Any]:
        return self.client.patch(
            f"{self.base}/permissions/{securable_type}/{full_name}",
            json={"changes": [{"principal": principal, "add": list(privileges)}]},
        )

    def revoke(
        self, securable_type: str, full_name: str, principal: str, privileges: Sequence[str]
    ) -> dict[str, Any]:
        return self.client.patch(
            f"{self.base}/permissions/{securable_type}/{full_name}",
            json={"changes": [{"principal": principal, "remove": list(privileges)}]},
        )

    # Higher-level workflows ----------------------------------------------------
    def setup_medallion(
        self,
        catalog: str,
        schemas: Sequence[str] = MEDALLION_SCHEMAS,
        permission_model: Mapping[str, Sequence[str]] = DEFAULT_PERMISSION_MODEL,
        storage_root: str | None = None,
    ) -> dict[str, Any]:
        """Idempotently create the catalog, its layer schemas and the standard grants."""
        created_catalog = self.ensure_catalog(
            catalog, "dataplatform lakehouse catalog", storage_root
        )
        created_schemas = [s for s in schemas if self.ensure_schema(catalog, s, f"{s} layer")]
        for principal, privileges in permission_model.items():
            self.grant("catalog", catalog, principal, privileges)
            logger.info("Granted %s on %s to %s", ", ".join(privileges), catalog, principal)
        return {
            "catalog_created": created_catalog,
            "schemas_created": created_schemas,
            "grants": len(permission_model),
        }

    def audit_catalog(self, catalog: str) -> dict[str, Any]:
        """Return a structured inventory of schemas, tables and grants for review."""
        schemas = [s for s in self.list_schemas(catalog) if not s["name"].startswith("__")]
        inventory = {
            "catalog": catalog,
            "schemas": [
                {
                    "name": s["name"],
                    "tables": [
                        {
                            "name": t["name"],
                            "type": t.get("table_type"),
                            "format": t.get("data_source_format"),
                        }
                        for t in self.list_tables(catalog, s["name"])
                    ],
                }
                for s in schemas
            ],
            "permissions": self.get_permissions("catalog", catalog),
        }
        logger.info("Audited catalog %s: %d schema(s)", catalog, len(schemas))
        return inventory
