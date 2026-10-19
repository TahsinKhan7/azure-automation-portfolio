"""Minimal HTTP client with retries, exponential backoff and typed errors.

Used as the REST fallback for Databricks and Azure Resource Manager APIs. Only JSON APIs are
supported, which is all the platform clients need.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Callable, Mapping
from typing import Any

import requests

logger = logging.getLogger(__name__)

RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 504})
DEFAULT_TIMEOUT_SECONDS = 30.0


class ApiError(RuntimeError):
    """Raised when an API call fails after retries."""

    def __init__(self, status: int | None, message: str, url: str = ""):
        self.status = status
        self.url = url
        super().__init__(f"HTTP {status} from {url}: {message}" if status else message)


class HttpClient:
    """JSON-over-HTTPS client with bearer-token auth and retry/backoff.

    Args:
        base_url: Root URL, e.g. ``https://adb-123.4.azuredatabricks.net``.
        token_provider: Callable returning a bearer token (lets tokens be refreshed, e.g. from
            ``DefaultAzureCredential``). A static string is also accepted.
        max_retries: Attempts after the first on retryable status codes / connection errors.
        backoff_seconds: Initial backoff; doubles on each retry. ``Retry-After`` is honoured.
        sleep: Injectable sleep function (tests pass a no-op).
    """

    def __init__(
        self,
        base_url: str,
        token_provider: Callable[[], str] | str,
        *,
        timeout: float = DEFAULT_TIMEOUT_SECONDS,
        max_retries: int = 3,
        backoff_seconds: float = 0.5,
        session: requests.Session | None = None,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self.base_url = base_url.rstrip("/")
        self._token_provider = (
            (lambda: token_provider) if isinstance(token_provider, str) else token_provider
        )
        self.timeout = timeout
        self.max_retries = max_retries
        self.backoff_seconds = backoff_seconds
        self.session = session or requests.Session()
        self._sleep = sleep

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._token_provider()}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "dataplatform/1.0",
        }

    def request(
        self,
        method: str,
        path: str,
        *,
        params: Mapping[str, Any] | None = None,
        json: Any = None,
    ) -> dict[str, Any]:
        """Perform a request and return the decoded JSON body (``{}`` when empty)."""
        url = path if path.startswith("http") else f"{self.base_url}/{path.lstrip('/')}"
        attempt = 0
        delay = self.backoff_seconds
        while True:
            try:
                response = self.session.request(
                    method.upper(),
                    url,
                    headers=self._headers(),
                    params=params,
                    json=json,
                    timeout=self.timeout,
                )
            except requests.RequestException as exc:
                if attempt >= self.max_retries:
                    raise ApiError(
                        None, f"connection error after {attempt + 1} attempt(s): {exc}", url
                    ) from exc
                logger.warning("%s %s failed (%s); retrying in %.1fs", method, url, exc, delay)
            else:
                if response.status_code < 400:
                    return _decode(response)
                if response.status_code not in RETRYABLE_STATUS or attempt >= self.max_retries:
                    raise ApiError(response.status_code, _error_message(response), url)
                retry_after = response.headers.get("Retry-After")
                if retry_after and retry_after.isdigit():
                    delay = float(retry_after)
                logger.warning(
                    "%s %s returned %s; retrying in %.1fs", method, url, response.status_code, delay
                )
            attempt += 1
            self._sleep(delay)
            delay *= 2

    def get(self, path: str, params: Mapping[str, Any] | None = None) -> dict[str, Any]:
        return self.request("GET", path, params=params)

    def post(self, path: str, json: Any = None) -> dict[str, Any]:
        return self.request("POST", path, json=json)

    def patch(self, path: str, json: Any = None) -> dict[str, Any]:
        return self.request("PATCH", path, json=json)

    def delete(self, path: str, params: Mapping[str, Any] | None = None) -> dict[str, Any]:
        return self.request("DELETE", path, params=params)


def _decode(response: requests.Response) -> dict[str, Any]:
    if not response.content:
        return {}
    try:
        body = response.json()
    except ValueError:
        return {"raw": response.text}
    return body if isinstance(body, dict) else {"items": body}


def _error_message(response: requests.Response) -> str:
    try:
        body = response.json()
    except ValueError:
        return response.text[:500]
    if isinstance(body, dict):
        return str(body.get("message") or body.get("error_code") or body.get("error") or body)[:500]
    return str(body)[:500]
