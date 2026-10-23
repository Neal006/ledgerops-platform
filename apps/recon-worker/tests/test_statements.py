import pytest

from recon.statements import parse_statement, to_minor


def test_to_minor_respects_currency_exponent():
    assert to_minor("12.34", "USD") == 1234
    assert to_minor("1.234", "KWD") == 1234
    assert to_minor("500", "JPY") == 500


def test_to_minor_rejects_excess_precision():
    with pytest.raises(ValueError, match="precision"):
        to_minor("1.005", "USD")


def test_to_minor_rejects_unknown_currency():
    with pytest.raises(ValueError, match="unsupported"):
        to_minor("1", "XYZ")


def test_parse_statement():
    positions = parse_statement("account_code,currency,balance\nBROKER:A,usd,10.50\n")
    assert [(p.account_code, p.currency, p.amount_minor) for p in positions] == [("BROKER:A", "USD", 1050)]


def test_parse_statement_rejects_duplicates():
    with pytest.raises(ValueError, match="duplicate"):
        parse_statement("account_code,currency,balance\nA,USD,1\nA,USD,2\n")


def test_parse_statement_requires_columns():
    with pytest.raises(ValueError, match="columns"):
        parse_statement("account,amount\nA,1\n")
