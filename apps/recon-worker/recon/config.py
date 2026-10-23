from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    environment: str
    book: str
    statement_uri: str
    # Ledger accounts that mirror external custody/cash positions are prefixed, e.g. BROKER:ALPACA:USD.
    account_prefix: str
    tolerance_minor: int
    pushgateway_url: str | None
    database_url: str | None

    @classmethod
    def from_env(cls) -> Config:
        statement_uri = os.environ.get("STATEMENT_URI")
        if not statement_uri:
            raise SystemExit("STATEMENT_URI is required (file path or s3://bucket/key)")
        return cls(
            environment=os.environ.get("APP_ENV", "local"),
            book=os.environ.get("LEDGER_BOOK", "IN"),
            statement_uri=statement_uri,
            account_prefix=os.environ.get("RECON_ACCOUNT_PREFIX", "BROKER:"),
            tolerance_minor=int(os.environ.get("RECON_TOLERANCE_MINOR", "0")),
            pushgateway_url=os.environ.get("PUSHGATEWAY_URL") or None,
            # Unset means libpq falls back to PGHOST/PGUSER/PGPASSWORD, as injected by ECS.
            database_url=os.environ.get("DATABASE_URL") or None,
        )
