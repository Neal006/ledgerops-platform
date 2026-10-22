-- Expand step of an expand/contract change: nullable column, no table rewrite, no default.
-- Backfill and NOT NULL (if ever needed) ship in later, separate deploys.
ALTER TABLE journal_entries ADD COLUMN external_ref text;
