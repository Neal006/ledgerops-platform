"""Pure reconciliation logic: compare two sets of positions and classify the breaks."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from recon.statements import Position


class BreakType(StrEnum):
    AMOUNT_MISMATCH = "amount_mismatch"
    MISSING_IN_LEDGER = "missing_in_ledger"
    MISSING_AT_BROKER = "missing_at_broker"


@dataclass(frozen=True)
class Break:
    type: BreakType
    account_code: str
    currency: str
    ledger_minor: int
    broker_minor: int

    @property
    def difference_minor(self) -> int:
        return self.ledger_minor - self.broker_minor


@dataclass(frozen=True)
class Result:
    matched: int
    breaks: list[Break]

    @property
    def clean(self) -> bool:
        return not self.breaks


def reconcile(ledger: list[Position], broker: list[Position], tolerance_minor: int = 0) -> Result:
    ledger_by_key = {(p.account_code, p.currency): p.amount_minor for p in ledger}
    broker_by_key = {(p.account_code, p.currency): p.amount_minor for p in broker}

    breaks: list[Break] = []
    matched = 0
    for key in sorted(ledger_by_key.keys() | broker_by_key.keys()):
        in_ledger, at_broker = key in ledger_by_key, key in broker_by_key
        ledger_amt, broker_amt = ledger_by_key.get(key, 0), broker_by_key.get(key, 0)

        if in_ledger and at_broker:
            if abs(ledger_amt - broker_amt) <= tolerance_minor:
                matched += 1
                continue
            kind = BreakType.AMOUNT_MISMATCH
        elif in_ledger:
            # A zero ledger balance with no broker line is fine: the account simply holds nothing.
            if ledger_amt == 0:
                matched += 1
                continue
            kind = BreakType.MISSING_AT_BROKER
        else:
            kind = BreakType.MISSING_IN_LEDGER

        breaks.append(Break(kind, key[0], key[1], ledger_amt, broker_amt))

    return Result(matched=matched, breaks=breaks)
