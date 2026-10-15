"""Rotate a Databricks personal access token and store it in Azure Key Vault.

Flow: create a new PAT with a short lifetime, write it to Key Vault (so consumers pick it
up on next read), then revoke any older tokens that carry the same rotation comment. If the
Key Vault write fails the new token is revoked immediately so no unreferenced token is left
alive.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

logger = logging.getLogger(__name__)

DEFAULT_LIFETIME_DAYS = 30
SECONDS_PER_DAY = 86_400


@dataclass(frozen=True)
class RotationResult:
    secret_name: str
    new_token_id: str
    revoked_token_ids: tuple[str, ...]
    expires_at: datetime


class TokenRotator:
    """Rotate PATs with the Databricks SDK and persist them with ``azure-keyvault-secrets``.

    Args:
        workspace_client: ``databricks.sdk.WorkspaceClient`` (tokens API).
        secret_client: ``azure.keyvault.secrets.SecretClient``.
        comment_prefix: Marks tokens managed by this rotator so only those are revoked.
    """

    def __init__(
        self,
        workspace_client: Any,
        secret_client: Any,
        comment_prefix: str = "dataplatform-rotated",
    ):
        self.w = workspace_client
        self.secrets = secret_client
        self.comment_prefix = comment_prefix

    def _comment(self, secret_name: str) -> str:
        return f"{self.comment_prefix}:{secret_name}"

    def managed_tokens(self, secret_name: str) -> list[Any]:
        comment = self._comment(secret_name)
        return [t for t in self.w.tokens.list() if getattr(t, "comment", None) == comment]

    def rotate(
        self,
        secret_name: str,
        lifetime_days: int = DEFAULT_LIFETIME_DAYS,
        revoke_previous: bool = True,
        now: datetime | None = None,
    ) -> RotationResult:
        """Create, store, then revoke previous tokens.

        Returns identifiers only, never the token value.
        """
        if lifetime_days <= 0:
            raise ValueError("lifetime_days must be positive")
        now = now or datetime.now(timezone.utc)
        previous_ids = (
            tuple(t.token_id for t in self.managed_tokens(secret_name)) if revoke_previous else ()
        )

        created = self.w.tokens.create(
            comment=self._comment(secret_name), lifetime_seconds=lifetime_days * SECONDS_PER_DAY
        )
        new_id = created.token_info.token_id
        expires_at = now + timedelta(days=lifetime_days)
        # Log lines carry no token identifiers and no Key Vault secret names; the
        # RotationResult returned to the caller carries both for reporting.
        logger.info("Created replacement token (expires %s)", expires_at.date())

        try:
            self.secrets.set_secret(
                secret_name,
                created.token_value,
                expires_on=expires_at,
                content_type="databricks-pat",
                tags={"rotated_at": now.isoformat(), "token_id": new_id},
            )
        except Exception:
            logger.exception("Key Vault write failed; revoking freshly created token")
            self.w.tokens.delete(token_id=new_id)
            raise

        revoked: list[str] = []
        for token_id in previous_ids:
            if token_id == new_id:
                continue
            self.w.tokens.delete(token_id=token_id)
            revoked.append(token_id)
            logger.info("Revoked previous token %d of %d", len(revoked), len(previous_ids))

        return RotationResult(secret_name, new_id, tuple(revoked), expires_at)

    def tokens_expiring_within(self, days: int, now: datetime | None = None) -> list[Any]:
        """Managed tokens whose expiry falls within ``days`` (for proactive rotation alerts)."""
        now = now or datetime.now(timezone.utc)
        horizon_ms = (now + timedelta(days=days)).timestamp() * 1000
        expiring = []
        for token in self.w.tokens.list():
            comment = getattr(token, "comment", "") or ""
            expiry = getattr(token, "expiry_time", None)
            if (
                comment.startswith(self.comment_prefix)
                and expiry
                and expiry != -1
                and expiry <= horizon_ms
            ):
                expiring.append(token)
        return expiring
