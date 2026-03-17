"""
Unity Catalog Manager
Python utility for managing Databricks Unity Catalog objects - catalogs, schemas,
tables, volumes and permissions via the REST API.
"""

import requests
import json
from typing import Optional


class UnityCatalogManager:

    def __init__(self, workspace_url: str, token: str):
        self.base = f"{workspace_url}/api/2.1/unity-catalog"
        self.headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    def _request(self, method, endpoint, body=None):
        url = f"{self.base}{endpoint}"
        r = requests.request(method, url, headers=self.headers, json=body)
        r.raise_for_status()
        return r.json() if r.text else {}

    # ---- Catalogs ----

    def list_catalogs(self):
        return self._request("GET", "/catalogs").get("catalogs", [])

    def create_catalog(self, name, comment=""):
        return self._request("POST", "/catalogs", {"name": name, "comment": comment})

    def delete_catalog(self, name, force=False):
        return self._request("DELETE", f"/catalogs/{name}?force={str(force).lower()}")

    # ---- Schemas ----

    def list_schemas(self, catalog_name):
        return self._request("GET", f"/schemas?catalog_name={catalog_name}").get("schemas", [])

    def create_schema(self, catalog_name, schema_name, comment=""):
        return self._request("POST", "/schemas", {
            "name": schema_name, "catalog_name": catalog_name, "comment": comment
        })

    def delete_schema(self, full_name):
        return self._request("DELETE", f"/schemas/{full_name}")

    # ---- Tables (metadata) ----

    def list_tables(self, catalog_name, schema_name):
        return self._request("GET", f"/tables?catalog_name={catalog_name}&schema_name={schema_name}").get("tables", [])

    def get_table(self, full_name):
        return self._request("GET", f"/tables/{full_name}")

    # ---- Permissions ----

    def get_permissions(self, securable_type, full_name):
        return self._request("GET", f"/permissions/{securable_type}/{full_name}")

    def grant_permissions(self, securable_type, full_name, principal, privileges):
        body = {"changes": [{"principal": principal, "add": privileges}]}
        return self._request("PATCH", f"/permissions/{securable_type}/{full_name}", body)

    def revoke_permissions(self, securable_type, full_name, principal, privileges):
        body = {"changes": [{"principal": principal, "remove": privileges}]}
        return self._request("PATCH", f"/permissions/{securable_type}/{full_name}", body)

    # ---- Setup medallion architecture ----

    def setup_medallion(self, catalog_name="enterprise_data"):
        """Create catalog with bronze/silver/gold schemas and standard permissions."""
        print(f"\n=== Setting up medallion architecture: {catalog_name} ===\n")

        try:
            self.create_catalog(catalog_name, "Enterprise data catalog")
            print(f"  Created catalog: {catalog_name}")
        except requests.HTTPError:
            print(f"  Catalog exists: {catalog_name}")

        for layer in ["bronze", "silver", "gold"]:
            try:
                self.create_schema(catalog_name, layer, f"{layer} layer - medallion architecture")
                print(f"  Created schema: {catalog_name}.{layer}")
            except requests.HTTPError:
                print(f"  Schema exists: {catalog_name}.{layer}")

        # Standard permission model
        permission_model = {
            "data-engineers":  ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE"],
            "data-analysts":   ["USE_CATALOG", "USE_SCHEMA", "SELECT"],
            "data-scientists": ["USE_CATALOG", "USE_SCHEMA", "SELECT", "CREATE_TABLE"],
            "bi-developers":   ["USE_CATALOG", "USE_SCHEMA", "SELECT"],
        }

        for principal, privs in permission_model.items():
            try:
                self.grant_permissions("catalog", catalog_name, principal, privs)
                print(f"  Granted to {principal}: {', '.join(privs)}")
            except requests.HTTPError as e:
                print(f"  Grant failed for {principal}: {e}")

        print("\nMedallion setup complete.")

    def audit_catalog(self, catalog_name):
        """Print full audit of catalog structure and permissions."""
        print(f"\n{'='*60}")
        print(f"Catalog Audit: {catalog_name}")
        print(f"{'='*60}\n")

        schemas = self.list_schemas(catalog_name)
        for schema in schemas:
            schema_name = schema["name"]
            if schema_name.startswith("__"):
                continue
            tables = self.list_tables(catalog_name, schema_name)
            print(f"  Schema: {catalog_name}.{schema_name} ({len(tables)} tables)")
            for t in tables:
                print(f"    {t['name']} | Type: {t.get('table_type', 'N/A')} | "
                      f"Format: {t.get('data_source_format', 'N/A')}")

        perms = self.get_permissions("catalog", catalog_name)
        print(f"\n  Permissions:")
        for p in perms.get("privilege_assignments", []):
            print(f"    {p['principal']}: {', '.join(p.get('privileges', []))}")


if __name__ == "__main__":
    import os
    mgr = UnityCatalogManager(
        os.environ.get("DATABRICKS_HOST", "https://adb-xxxx.azuredatabricks.net"),
        os.environ.get("DATABRICKS_TOKEN", "")
    )
    mgr.setup_medallion("enterprise_data")
    mgr.audit_catalog("enterprise_data")
