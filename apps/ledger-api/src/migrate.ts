import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

// Arbitrary constant shared by every migrator instance; only one can hold it at a time.
const ADVISORY_LOCK_ID = 727_001;
const NO_TRANSACTION_DIRECTIVE = "-- migrate:no-transaction";

export interface Migration {
  name: string;
  sql: string;
  checksum: string;
  transactional: boolean;
}

export interface MigrateOptions {
  connectionString?: string;
  migrationsDir: string;
  // Fail fast instead of queueing behind a long-running query and blocking all traffic behind us.
  lockTimeoutMs?: number;
  statementTimeoutMs?: number;
  log?: (msg: string) => void;
}

export async function loadMigrations(dir: string): Promise<Migration[]> {
  const files = (await readdir(dir)).filter((f) => f.endsWith(".sql")).sort();
  return Promise.all(
    files.map(async (name) => {
      const sql = await readFile(path.join(dir, name), "utf8");
      return {
        name,
        sql,
        checksum: createHash("sha256").update(sql).digest("hex"),
        transactional: !sql.trimStart().startsWith(NO_TRANSACTION_DIRECTIVE),
      };
    }),
  );
}

export async function migrate(opts: MigrateOptions): Promise<string[]> {
  const log = opts.log ?? ((msg) => console.log(JSON.stringify({ msg, component: "migrate" })));
  const client = new pg.Client({ connectionString: opts.connectionString, application_name: "ledger-migrate" });
  await client.connect();
  const applied: string[] = [];

  try {
    await client.query(`SET lock_timeout = ${Number(opts.lockTimeoutMs ?? 5000)}`);
    await client.query(`SET statement_timeout = ${Number(opts.statementTimeoutMs ?? 600_000)}`);

    log("waiting for migration advisory lock");
    await client.query("SELECT pg_advisory_lock($1)", [ADVISORY_LOCK_ID]);

    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        name        text PRIMARY KEY,
        checksum    text NOT NULL,
        applied_at  timestamptz NOT NULL DEFAULT now()
      )`);

    const { rows } = await client.query<{ name: string; checksum: string }>(
      "SELECT name, checksum FROM schema_migrations",
    );
    const done = new Map(rows.map((r) => [r.name, r.checksum]));

    for (const m of await loadMigrations(opts.migrationsDir)) {
      const previous = done.get(m.name);
      if (previous !== undefined) {
        // Editing an applied migration silently diverges environments; refuse loudly instead.
        if (previous !== m.checksum) {
          throw new Error(`migration ${m.name} was modified after being applied`);
        }
        continue;
      }

      log(`applying ${m.name}${m.transactional ? "" : " (non-transactional)"}`);
      const started = Date.now();
      if (m.transactional) {
        await client.query("BEGIN");
        try {
          await client.query(m.sql);
          await client.query("INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)", [m.name, m.checksum]);
          await client.query("COMMIT");
        } catch (err) {
          await client.query("ROLLBACK");
          throw err;
        }
      } else {
        await client.query(m.sql);
        await client.query("INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)", [m.name, m.checksum]);
      }
      log(`applied ${m.name} in ${Date.now() - started}ms`);
      applied.push(m.name);
    }

    log(applied.length ? `applied ${applied.length} migration(s)` : "schema up to date");
    return applied;
  } finally {
    await client.query("SELECT pg_advisory_unlock($1)", [ADVISORY_LOCK_ID]).catch(() => undefined);
    await client.end();
  }
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const migrationsDir =
    process.env.MIGRATIONS_DIR ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../migrations");
  migrate({
    connectionString: process.env.DATABASE_URL,
    migrationsDir,
    lockTimeoutMs: process.env.MIGRATION_LOCK_TIMEOUT_MS ? Number(process.env.MIGRATION_LOCK_TIMEOUT_MS) : undefined,
  }).catch((err: unknown) => {
    console.error(JSON.stringify({ msg: "migration failed", component: "migrate", error: String(err) }));
    process.exit(1);
  });
}
