-- migrate:no-transaction
-- CONCURRENTLY avoids holding a write-blocking lock on a hot table, but cannot run inside
-- a transaction, hence the directive above.
CREATE INDEX CONCURRENTLY IF NOT EXISTS journal_entries_external_ref_idx
  ON journal_entries (external_ref)
  WHERE external_ref IS NOT NULL;
