from recon.reconcile import BreakType, reconcile
from recon.statements import Position


def pos(code: str, amount: int, currency: str = "USD") -> Position:
    return Position(code, currency, amount)


def test_clean_when_balances_match():
    result = reconcile([pos("BROKER:A", 100)], [pos("BROKER:A", 100)])
    assert result.clean
    assert result.matched == 1


def test_amount_mismatch_reports_signed_difference():
    result = reconcile([pos("BROKER:A", 100)], [pos("BROKER:A", 90)])
    (b,) = result.breaks
    assert b.type is BreakType.AMOUNT_MISMATCH
    assert b.difference_minor == 10


def test_tolerance_absorbs_small_differences():
    assert reconcile([pos("BROKER:A", 100)], [pos("BROKER:A", 99)], tolerance_minor=1).clean


def test_position_only_at_broker_is_missing_in_ledger():
    (b,) = reconcile([], [pos("BROKER:A", 5)]).breaks
    assert b.type is BreakType.MISSING_IN_LEDGER


def test_nonzero_ledger_balance_absent_at_broker_is_a_break():
    (b,) = reconcile([pos("BROKER:A", 5)], []).breaks
    assert b.type is BreakType.MISSING_AT_BROKER


def test_zero_ledger_balance_absent_at_broker_is_fine():
    assert reconcile([pos("BROKER:A", 0)], []).clean


def test_same_account_in_different_currencies_is_compared_separately():
    ledger = [pos("BROKER:A", 100, "USD"), pos("BROKER:A", 50, "AED")]
    broker = [pos("BROKER:A", 100, "USD"), pos("BROKER:A", 60, "AED")]
    (b,) = reconcile(ledger, broker).breaks
    assert b.currency == "AED"
