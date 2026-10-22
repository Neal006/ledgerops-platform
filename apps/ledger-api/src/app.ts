import Fastify, { type FastifyInstance } from "fastify";
import type pg from "pg";
import type { Config } from "./config.js";

export interface AppDeps {
  config: Config;
  pool: pg.Pool;
}

export function buildApp({ config, pool }: AppDeps): FastifyInstance {
  const app = Fastify({
    logger: {
      level: config.logLevel,
      base: { service: config.serviceName, env: config.environment, book: config.book },
      redact: ["req.headers.authorization", "req.headers.cookie"],
    },
    requestIdHeader: "x-request-id",
    disableRequestLogging: false,
  });

  let shuttingDown = false;
  app.decorate("markShuttingDown", () => {
    shuttingDown = true;
  });

  // Liveness: the process is up. Never touches dependencies, so a slow DB can't trigger restarts.
  app.get("/healthz", async () => ({ status: "ok" }));

  // Readiness: safe to receive traffic. The ALB target group health check points here.
  app.get("/readyz", async (_req, reply) => {
    if (shuttingDown) return reply.code(503).send({ status: "draining" });
    try {
      await pool.query("SELECT 1");
      return { status: "ready" };
    } catch (err) {
      app.log.warn({ err }, "readiness check failed");
      return reply.code(503).send({ status: "db_unavailable" });
    }
  });

  return app;
}

declare module "fastify" {
  interface FastifyInstance {
    markShuttingDown: () => void;
  }
}
