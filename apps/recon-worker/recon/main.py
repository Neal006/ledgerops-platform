"""Entry point: run one reconciliation pass and report the outcome.

Exit codes: 0 = the run completed (breaks are reported via metrics and logs, not the exit code, so a
known break doesn't look like a crashed job); 1 = the run itself failed.
"""

from __future__ import annotations

import json
import logging
import sys
import time

from recon.config import Config
from recon.ledger import fetch_balances
from recon.metrics import emf_record, emit_emf, push_prometheus
from recon.reconcile import reconcile
from recon.statements import parse_statement, read_text


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {"level": record.levelname.lower(), "msg": record.getMessage(), "service": "recon-worker"}
        payload.update(getattr(record, "fields", {}))
        if record.exc_info:
            payload["error"] = self.formatException(record.exc_info)
        return json.dumps(payload)


log = logging.getLogger("recon")


def run(config: Config) -> int:
    started = time.monotonic()
    ledger = fetch_balances(config.database_url, config.book, config.account_prefix)
    broker = parse_statement(read_text(config.statement_uri))
    result = reconcile(ledger, broker, config.tolerance_minor)
    duration = time.monotonic() - started

    for b in result.breaks:
        log.warning(
            "reconciliation break",
            extra={
                "fields": {
                    "break_type": b.type.value,
                    "account_code": b.account_code,
                    "currency": b.currency,
                    "ledger_minor": b.ledger_minor,
                    "broker_minor": b.broker_minor,
                    "difference_minor": b.difference_minor,
                }
            },
        )

    emit_emf(emf_record(result, config.environment, config.book, duration))
    if config.pushgateway_url:
        push_prometheus(config.pushgateway_url, result, config.environment, config.book, duration)

    log.info(
        "reconciliation complete",
        extra={"fields": {"matched": result.matched, "breaks": len(result.breaks), "duration_s": duration}},
    )
    return 0


def main() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(level=logging.INFO, handlers=[handler])
    try:
        sys.exit(run(Config.from_env()))
    except Exception:
        log.exception("reconciliation run failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
