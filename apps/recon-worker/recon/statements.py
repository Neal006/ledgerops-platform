"""Loading broker/custodian statements from a local file or S3."""

from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from urllib.parse import urlparse

# ISO 4217 minor-unit exponents for the currencies we settle in. Anything else must be added explicitly.
MINOR_UNITS = {"USD": 2, "AED": 2, "INR": 2, "EUR": 2, "GBP": 2, "JPY": 0, "KWD": 3, "BHD": 3}


@dataclass(frozen=True)
class Position:
    account_code: str
    currency: str
    amount_minor: int


def to_minor(amount: str, currency: str) -> int:
    if currency not in MINOR_UNITS:
        raise ValueError(f"unsupported currency {currency!r}")
    scaled = Decimal(amount).scaleb(MINOR_UNITS[currency])
    if scaled != scaled.to_integral_value():
        raise ValueError(f"{amount} {currency} has more precision than the currency allows")
    return int(scaled)


def read_text(uri: str) -> str:
    parsed = urlparse(uri)
    if parsed.scheme == "s3":
        import boto3  # imported lazily so local runs and tests don't need AWS credentials

        body = boto3.client("s3").get_object(Bucket=parsed.netloc, Key=parsed.path.lstrip("/"))["Body"]
        return body.read().decode("utf-8")
    return Path(parsed.path if parsed.scheme == "file" else uri).read_text(encoding="utf-8")


def parse_statement(text: str) -> list[Position]:
    """Parse a CSV statement with columns: account_code, currency, balance (major units)."""
    reader = csv.DictReader(io.StringIO(text))
    required = {"account_code", "currency", "balance"}
    if reader.fieldnames is None or not required.issubset(reader.fieldnames):
        raise ValueError(f"statement must have columns {sorted(required)}, got {reader.fieldnames}")

    positions: dict[tuple[str, str], Position] = {}
    for line_no, row in enumerate(reader, start=2):
        key = (row["account_code"].strip(), row["currency"].strip().upper())
        if key in positions:
            raise ValueError(f"line {line_no}: duplicate position for {key}")
        positions[key] = Position(key[0], key[1], to_minor(row["balance"].strip(), key[1]))
    return list(positions.values())
