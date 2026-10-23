import { createHash } from "node:crypto";
import type pg from "pg";
import { withTransaction } from "./db.js";

export type AccountType = "asset" | "liability" | "equity" | "revenue" | "expense";

export interface NewAccount {
  code: string;
  name: string;
  type: AccountType;
  currency: string;
}

export interface PostingInput {
  account_code: string;
  amount_minor: string;
  currency: string;
}

export interface JournalInput {
  idempotency_key: string;
  description: string;
  occurred_at: string;
  external_ref?: string;
  postings: PostingInput[];
}

export class LedgerError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

/**
 * Pure validation of the double-entry invariant: every currency in a journal entry must net to zero.
 * Kept free of I/O so it can be unit tested exhaustively.
 */
export function validateJournal(input: JournalInput): void {
  if (input.postings.length < 2) {
    throw new LedgerError(422, "too_few_postings", "a journal entry needs at least two postings");
  }

  const totals = new Map<string, bigint>();
  const seen = new Set<string>();
  for (const p of input.postings) {
    if (!/^-?[1-9]\d{0,17}$/.test(p.amount_minor)) {
      throw new LedgerError(422, "invalid_amount", `amount_minor must be a non-zero integer, got "${p.amount_minor}"`);
    }
    const key = `${p.account_code}:${p.currency}`;
    if (seen.has(key)) {
      throw new LedgerError(422, "duplicate_posting", `account ${p.account_code} appears more than once`);
    }
    seen.add(key);
    totals.set(p.currency, (totals.get(p.currency) ?? 0n) + BigInt(p.amount_minor));
  }

  for (const [currency, total] of totals) {
    if (total !== 0n) {
      throw new LedgerError(422, "unbalanced", `postings in ${currency} sum to ${total}, expected 0`);
    }
  }
}

export function requestHash(input: JournalInput): string {
  const canonical = {
    description: input.description,
    occurred_at: new Date(input.occurred_at).toISOString(),
    external_ref: input.external_ref ?? null,
    postings: [...input.postings]
      .map((p) => [p.account_code, p.currency, p.amount_minor])
      .sort((a, b) => a.join().localeCompare(b.join())),
  };
  return createHash("sha256").update(JSON.stringify(canonical)).digest("hex");
}

export class Ledger {
  constructor(
    private readonly pool: pg.Pool,
    // The regulated book this deployment serves. Accounts from the other jurisdiction are invisible.
    private readonly book: string,
  ) {}

  async createAccount(a: NewAccount) {
    try {
      const { rows } = await this.pool.query(
        `INSERT INTO accounts (code, name, type, currency, book)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, code, name, type, currency, book, created_at`,
        [a.code, a.name, a.type, a.currency, this.book],
      );
      return rows[0];
    } catch (err) {
      if ((err as { code?: string }).code === "23505") {
        throw new LedgerError(409, "account_exists", `account ${a.code} already exists`);
      }
      throw err;
    }
  }

  async getBalance(code: string) {
    const { rows } = await this.pool.query(
      `SELECT a.code, a.currency, a.type,
              COALESCE(sum(p.amount_minor), 0)::bigint AS balance_minor,
              count(p.id)::bigint AS posting_count
         FROM accounts a
         LEFT JOIN postings p ON p.account_id = a.id
        WHERE a.code = $1 AND a.book = $2
        GROUP BY a.id`,
      [code, this.book],
    );
    if (rows.length === 0) throw new LedgerError(404, "account_not_found", `account ${code} not found`);
    return rows[0];
  }

  async listBalances() {
    const { rows } = await this.pool.query(
      `SELECT a.code, a.currency, COALESCE(sum(p.amount_minor), 0)::bigint AS balance_minor
         FROM accounts a
         LEFT JOIN postings p ON p.account_id = a.id
        WHERE a.book = $1
        GROUP BY a.id
        ORDER BY a.code`,
      [this.book],
    );
    return rows;
  }

  /** Posts a journal entry. Idempotent on idempotency_key: a replay returns the original entry. */
  async postJournal(input: JournalInput): Promise<{ id: string; replayed: boolean }> {
    validateJournal(input);
    const hash = requestHash(input);

    return withTransaction(this.pool, async (client) => {
      const inserted = await client.query<{ id: string }>(
        `INSERT INTO journal_entries (idempotency_key, request_hash, description, occurred_at, external_ref)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (idempotency_key) DO NOTHING
         RETURNING id`,
        [input.idempotency_key, hash, input.description, input.occurred_at, input.external_ref ?? null],
      );

      if (inserted.rows.length === 0) {
        const existing = await client.query<{ id: string; request_hash: string }>(
          "SELECT id, request_hash FROM journal_entries WHERE idempotency_key = $1",
          [input.idempotency_key],
        );
        const row = existing.rows[0]!;
        if (row.request_hash !== hash) {
          throw new LedgerError(409, "idempotency_conflict", "idempotency key reused with a different payload");
        }
        return { id: row.id, replayed: true };
      }

      const entryId = inserted.rows[0]!.id;
      const codes = input.postings.map((p) => p.account_code);
      const accounts = await client.query<{ id: string; code: string; currency: string }>(
        "SELECT id, code, currency FROM accounts WHERE code = ANY($1) AND book = $2",
        [codes, this.book],
      );
      const byCode = new Map(accounts.rows.map((r) => [r.code, r]));

      for (const p of input.postings) {
        const account = byCode.get(p.account_code);
        if (!account) throw new LedgerError(422, "unknown_account", `account ${p.account_code} not found`);
        if (account.currency !== p.currency) {
          throw new LedgerError(422, "currency_mismatch", `account ${p.account_code} is denominated in ${account.currency}`);
        }
      }

      await client.query(
        `INSERT INTO postings (journal_entry_id, account_id, amount_minor, currency)
         SELECT $1, unnest($2::uuid[]), unnest($3::bigint[]), unnest($4::text[])`,
        [
          entryId,
          input.postings.map((p) => byCode.get(p.account_code)!.id),
          input.postings.map((p) => p.amount_minor),
          input.postings.map((p) => p.currency),
        ],
      );
      return { id: entryId, replayed: false };
    });
  }
}
