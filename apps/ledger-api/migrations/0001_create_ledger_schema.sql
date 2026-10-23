-- Core double-entry ledger schema.
-- Amounts are stored as signed integers in minor units (debit > 0, credit < 0).

CREATE TABLE accounts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL UNIQUE,
  name        text NOT NULL,
  type        text NOT NULL CHECK (type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
  currency    text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  book        text NOT NULL CHECK (book IN ('IN', 'AE')),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE journal_entries (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key  text NOT NULL UNIQUE,
  request_hash     text NOT NULL,
  description      text NOT NULL,
  occurred_at      timestamptz NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE postings (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  journal_entry_id  uuid NOT NULL REFERENCES journal_entries (id),
  account_id        uuid NOT NULL REFERENCES accounts (id),
  amount_minor      bigint NOT NULL CHECK (amount_minor <> 0),
  currency          text NOT NULL CHECK (currency ~ '^[A-Z]{3}$')
);

-- Indexes on a table created in this same migration: it is empty, so a blocking build is instant.
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX postings_journal_entry_id_idx ON postings (journal_entry_id);
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX postings_account_id_idx ON postings (account_id);

-- Defence in depth: the API validates balance, but the database refuses to commit an
-- unbalanced journal entry even if a buggy code path or a manual session tries to.
CREATE FUNCTION assert_journal_entry_balanced() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  unbalanced record;
BEGIN
  SELECT currency, sum(amount_minor) AS total
    INTO unbalanced
    FROM postings
   WHERE journal_entry_id = NEW.journal_entry_id
   GROUP BY currency
  HAVING sum(amount_minor) <> 0
   LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'journal entry % is unbalanced in % by %',
      NEW.journal_entry_id, unbalanced.currency, unbalanced.total
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER postings_balanced
  AFTER INSERT OR UPDATE ON postings
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION assert_journal_entry_balanced();

-- The ledger is append-only. Corrections are new reversing entries, never edits.
CREATE FUNCTION reject_ledger_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is append-only', TG_TABLE_NAME USING ERRCODE = 'insufficient_privilege';
END;
$$;

CREATE TRIGGER postings_append_only
  BEFORE UPDATE OR DELETE ON postings
  FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();

CREATE TRIGGER journal_entries_append_only
  BEFORE UPDATE OR DELETE ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
