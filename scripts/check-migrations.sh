#!/usr/bin/env bash
# Migration safety gate, run in CI on every pull request.
#   1. Applied migrations are immutable: editing or deleting one that exists on the base branch fails.
#   2. CREATE INDEX CONCURRENTLY must be in a file marked "-- migrate:no-transaction".
#   3. Destructive DDL (DROP / RENAME / SET NOT NULL / type changes) is blocked unless the file opts in
#      with "-- migrate:allow-destructive <reason>", forcing the expand/contract pattern by default.
set -euo pipefail

BASE_REF="${BASE_REF:-origin/main}"
DIR="apps/ledger-api/migrations"
status=0
fail() { echo "::error file=$1::$2"; status=1; }

if git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  while IFS=$'\t' read -r change path _; do
    [[ "$path" == "$DIR"/*.sql ]] || continue
    case "$change" in
      M*|D*|R*) fail "$path" "already-merged migrations are immutable; add a new migration instead ($change)" ;;
    esac
  done < <(git diff --name-status "$BASE_REF"...HEAD -- "$DIR")
else
  echo "base ref $BASE_REF not found; skipping immutability check"
fi

for f in "$DIR"/*.sql; do
  name=$(basename "$f")
  [[ "$name" =~ ^[0-9]{4}_[a-z0-9_]+\.sql$ ]] || fail "$f" "migration names must look like 0001_snake_case.sql"

  body=$(grep -v '^[[:space:]]*--' "$f" | tr '[:lower:]' '[:upper:]')
  if grep -q 'CONCURRENTLY' <<<"$body" && ! head -n1 "$f" | grep -q -- '-- migrate:no-transaction'; then
    fail "$f" "CONCURRENTLY cannot run in a transaction; first line must be '-- migrate:no-transaction'"
  fi

  if grep -Eq 'DROP[[:space:]]+(TABLE|COLUMN)|RENAME[[:space:]]+(TO|COLUMN)|SET[[:space:]]+NOT[[:space:]]+NULL|ALTER[[:space:]]+COLUMN[^;]*TYPE' <<<"$body" \
     && ! grep -q -- '-- migrate:allow-destructive' "$f"; then
    fail "$f" "destructive DDL breaks the running app version during deploy; use expand/contract or add '-- migrate:allow-destructive <reason>'"
  fi
done

[[ $status -eq 0 ]] && echo "migration checks passed"
exit $status
