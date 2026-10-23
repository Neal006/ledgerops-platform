export interface Config {
  port: number;
  host: string;
  logLevel: string;
  serviceName: string;
  environment: string;
  // Book identifies the regulated entity this deployment serves (IN = IFSCA/GIFT City, AE = UAE).
  book: string;
  db: {
    connectionString: string | undefined;
    poolMax: number;
    statementTimeoutMs: number;
    idleTimeoutMs: number;
  };
  shutdownGraceMs: number;
}

function int(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const value = Number.parseInt(raw, 10);
  if (Number.isNaN(value)) throw new Error(`${name} must be an integer, got "${raw}"`);
  return value;
}

// Guardrail: a developer machine must never point at a managed (production-class) database.
export function assertSafeTarget(environment: string, connectionString: string | undefined): void {
  if (environment !== "local") return;
  const host = connectionString ? new URL(connectionString).hostname : (process.env.PGHOST ?? "");
  if (/\.rds\.amazonaws\.com$|\.proxy-[a-z0-9]+\./i.test(host)) {
    throw new Error(`APP_ENV=local refuses to connect to managed database host ${host}`);
  }
}

export function loadConfig(): Config {
  const environment = process.env.APP_ENV ?? "local";
  assertSafeTarget(environment, process.env.DATABASE_URL);
  return {
    port: int("PORT", 3000),
    host: process.env.HOST ?? "0.0.0.0",
    logLevel: process.env.LOG_LEVEL ?? "info",
    serviceName: process.env.SERVICE_NAME ?? "ledger-api",
    environment,
    book: process.env.LEDGER_BOOK ?? "IN",
    db: {
      // When unset, pg falls back to the standard PGHOST/PGUSER/PGPASSWORD/PGSSLMODE variables,
      // which is how ECS injects the RDS-managed secret.
      connectionString: process.env.DATABASE_URL,
      poolMax: int("DB_POOL_MAX", 10),
      statementTimeoutMs: int("DB_STATEMENT_TIMEOUT_MS", 5000),
      idleTimeoutMs: int("DB_IDLE_TIMEOUT_MS", 30000),
    },
    shutdownGraceMs: int("SHUTDOWN_GRACE_MS", 25000),
  };
}
