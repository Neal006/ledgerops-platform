#!/usr/bin/env bash
# Seeds the local ledger with a broker cash account, a client account and one deposit.
set -euo pipefail
API="${API:-http://localhost:3000}"

post() { curl -fsS -X POST "$API$1" -H 'content-type: application/json' -d "$2"; echo; }

post /v1/accounts '{"code":"BROKER:ALPACA:USD","name":"Alpaca omnibus cash","type":"asset","currency":"USD"}' || true
post /v1/accounts '{"code":"CLIENT:1001:USD","name":"Client 1001 cash","type":"liability","currency":"USD"}' || true
post /v1/journal-entries '{
  "idempotency_key": "seed-deposit-0001",
  "description": "Client 1001 LRS deposit",
  "occurred_at": "2026-10-01T09:30:00Z",
  "postings": [
    {"account_code": "BROKER:ALPACA:USD", "amount_minor": "250000", "currency": "USD"},
    {"account_code": "CLIENT:1001:USD",   "amount_minor": "-250000", "currency": "USD"}
  ]
}'
curl -fsS "$API/v1/accounts/balances"; echo
