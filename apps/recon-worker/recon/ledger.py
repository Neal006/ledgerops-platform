"""Read-only access to ledger balances."""

from __future__ import annotations

import psycopg

from recon.statements import Position

BALANCES_SQL = """
SELECT a.code, a.currency, COALESCE(sum(p.amount_minor), 0)::bigint
  FROM accounts a
  LEFT JOIN postings p ON p.account_id = a.id
 WHERE a.book = %(book)s AND a.code LIKE %(prefix)s
 GROUP BY a.id
"""


def fetch_balances(database_url: str | None, book: str, prefix: str) -> list[Position]:
    # A read-only transaction guarantees this job can never write to the ledger, even by accident.
    with psycopg.connect(database_url or "", application_name="recon-worker") as conn:
        conn.read_only = True
        with conn.cursor() as cur:
            cur.execute("SET statement_timeout = '60s'")
            cur.execute(BALANCES_SQL, {"book": book, "prefix": prefix.replace("%", r"\%") + "%"})
            return [Position(code, currency.strip(), int(amount)) for code, currency, amount in cur]
