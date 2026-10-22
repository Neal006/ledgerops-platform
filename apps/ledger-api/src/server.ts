import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { createPool } from "./db.js";

const config = loadConfig();
const pool = createPool(config.db);
const app = buildApp({ config, pool });

async function shutdown(signal: string): Promise<void> {
  app.log.info({ signal }, "shutdown requested, draining");
  // Fail readiness first so the load balancer stops routing new requests, then close.
  app.markShuttingDown();
  const timer = setTimeout(() => {
    app.log.error("graceful shutdown timed out, forcing exit");
    process.exit(1);
  }, config.shutdownGraceMs);
  timer.unref();

  await app.close();
  await pool.end();
  app.log.info("shutdown complete");
  process.exit(0);
}

process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));

try {
  await app.listen({ port: config.port, host: config.host });
} catch (err) {
  app.log.error({ err }, "failed to start");
  process.exit(1);
}
