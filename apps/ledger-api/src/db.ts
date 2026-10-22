import pg from "pg";
import type { Config } from "./config.js";

// Return BIGINT (int8) as string so minor-unit amounts never lose precision.
pg.types.setTypeParser(pg.types.builtins.INT8, (v) => v);

export function createPool(config: Config["db"]): pg.Pool {
  return new pg.Pool({
    connectionString: config.connectionString,
    max: config.poolMax,
    idleTimeoutMillis: config.idleTimeoutMs,
    connectionTimeoutMillis: 3000,
    statement_timeout: config.statementTimeoutMs,
    application_name: "ledger-api",
  });
}

export async function withTransaction<T>(
  pool: pg.Pool,
  fn: (client: pg.PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw err;
  } finally {
    client.release();
  }
}
