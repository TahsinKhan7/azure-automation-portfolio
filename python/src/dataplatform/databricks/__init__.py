"""Databricks and Azure platform clients.

Where the Databricks SDK offers a natural, typed API (jobs, tokens) it is used directly.
Simpler read-mostly operations (clusters, Unity Catalog metadata, ADF run queries) go
through :class:`dataplatform.databricks.http.HttpClient`, a small ``requests`` wrapper with
retries and backoff, which keeps them easy to test without network access.
"""
