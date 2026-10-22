// Runs against a real Postgres when DATABASE_URL is set (CI provides a service container).
import assert from "node:assert/strict";
import path from "node:path";
import { after, before, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import pg from "pg";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { createPool } from "../src/db.js";
import { migrate } from "../src/migrate.js";

const url = process.env.DATABASE_URL;
const migrationsDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../migrations");

describe("ledger against Postgres", { skip: !url && "DATABASE_URL not set" }, () => {
  let pool: pg.Pool;
  let app: ReturnType<typeof buildApp>;
  const run = Date.now().toString(36);
  const cash = `BROKER:TEST:${run}`;
  const client = `CLIENT:${run}`;

  before(async () => {
    await migrate({ connectionString: url, migrationsDir, log: () => undefined });
    pool = createPool({ ...loadConfig().db, connectionString: url });
    app = buildApp({ config: { ...loadConfig(), logLevel: "silent", book: "IN" }, pool });
  });

  after(async () => {
    await app.close();
    await pool.end();
  });

  it("is idempotent when migrations run twice", async () => {
    const applied = await migrate({ connectionString: url, migrationsDir, log: () => undefined });
    assert.deepEqual(applied, []);
  });

  it("creates accounts and posts a balanced entry", async () => {
    for (const [code, type] of [
      [cash, "asset"],
      [client, "liability"],
    ]) {
      const res = await app.inject({
        method: "POST",
        url: "/v1/accounts",
        payload: { code, name: code, type, currency: "USD" },
      });
      assert.equal(res.statusCode, 201, res.body);
    }

    const entry = {
      idempotency_key: `dep-${run}`,
      description: "deposit",
      occurred_at: new Date().toISOString(),
      postings: [
        { account_code: cash, amount_minor: "250000", currency: "USD" },
        { account_code: client, amount_minor: "-250000", currency: "USD" },
      ],
    };
    const first = await app.inject({ method: "POST", url: "/v1/journal-entries", payload: entry });
    assert.equal(first.statusCode, 201, first.body);

    const replay = await app.inject({ method: "POST", url: "/v1/journal-entries", payload: entry });
    assert.equal(replay.statusCode, 200);
    assert.equal(replay.json().id, first.json().id);

    const conflict = await app.inject({
      method: "POST",
      url: "/v1/journal-entries",
      payload: { ...entry, description: "different" },
    });
    assert.equal(conflict.statusCode, 409);

    const balance = await app.inject({ method: "GET", url: `/v1/accounts/${encodeURIComponent(cash)}/balance` });
    assert.equal(balance.json().balance_minor, "250000");
  });

  it("database rejects unbalanced postings even when the API is bypassed", async () => {
    const c = await pool.connect();
    try {
      await c.query("BEGIN");
      const { rows } = await c.query(
        "INSERT INTO journal_entries (idempotency_key, request_hash, description, occurred_at) VALUES ($1, 'x', 'bypass', now()) RETURNING id",
        [`bypass-${run}`],
      );
      await c.query(
        "INSERT INTO postings (journal_entry_id, account_id, amount_minor, currency) SELECT $1, id, 100, 'USD' FROM accounts WHERE code = $2",
        [rows[0].id, cash],
      );
      await assert.rejects(c.query("COMMIT"), /unbalanced/);
    } finally {
      await c.query("ROLLBACK").catch(() => undefined);
      c.release();
    }
  });

  it("database refuses to mutate posted history", async () => {
    await assert.rejects(pool.query("DELETE FROM postings"), /append-only/);
  });
});
