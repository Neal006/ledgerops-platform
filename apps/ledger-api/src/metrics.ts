import type { FastifyInstance } from "fastify";
import type pg from "pg";
import client from "prom-client";

export interface Metrics {
  registry: client.Registry;
  journalEntries: client.Counter<"result">;
}

export function registerMetrics(app: FastifyInstance, pool: pg.Pool, labels: Record<string, string>): Metrics {
  const registry = new client.Registry();
  registry.setDefaultLabels(labels);
  client.collectDefaultMetrics({ register: registry });

  // Buckets are tuned around the 300ms latency SLO so the SLO boundary is an exact bucket edge.
  const httpDuration = new client.Histogram({
    name: "http_server_request_duration_seconds",
    help: "HTTP request latency",
    labelNames: ["method", "route", "status_code"],
    buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2.5, 5],
    registers: [registry],
  });

  const journalEntries = new client.Counter({
    name: "ledger_journal_entries_total",
    help: "Journal entry post attempts by outcome",
    labelNames: ["result"],
    registers: [registry],
  });

  // Pool saturation is the leading indicator of connection exhaustion; alert on waiting > 0 sustained.
  new client.Gauge({
    name: "db_pool_connections",
    help: "Postgres pool connections by state",
    labelNames: ["state"],
    registers: [registry],
    collect() {
      this.set({ state: "total" }, pool.totalCount);
      this.set({ state: "idle" }, pool.idleCount);
      this.set({ state: "waiting" }, pool.waitingCount);
    },
  });

  app.addHook("onResponse", async (req, reply) => {
    // Use the route template, never the raw URL, to keep label cardinality bounded.
    const route = req.routeOptions.url ?? "unmatched";
    if (route === "/metrics") return;
    httpDuration.observe(
      { method: req.method, route, status_code: String(reply.statusCode) },
      reply.elapsedTime / 1000,
    );
  });

  app.get("/metrics", async (_req, reply) => {
    reply.header("content-type", registry.contentType);
    return registry.metrics();
  });

  return { registry, journalEntries };
}
