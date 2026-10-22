import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type pg from "pg";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";

function fakePool(healthy: boolean): pg.Pool {
  return {
    query: async () => {
      if (!healthy) throw new Error("connection refused");
      return { rows: [] };
    },
    totalCount: 2,
    idleCount: 1,
    waitingCount: 0,
  } as unknown as pg.Pool;
}

const config = { ...loadConfig(), logLevel: "silent" };

describe("probes", () => {
  it("liveness does not depend on the database", async () => {
    const app = buildApp({ config, pool: fakePool(false) });
    const res = await app.inject({ method: "GET", url: "/healthz" });
    assert.equal(res.statusCode, 200);
  });

  it("readiness fails when the database is unreachable", async () => {
    const app = buildApp({ config, pool: fakePool(false) });
    const res = await app.inject({ method: "GET", url: "/readyz" });
    assert.equal(res.statusCode, 503);
  });

  it("readiness fails while draining for shutdown", async () => {
    const app = buildApp({ config, pool: fakePool(true) });
    assert.equal((await app.inject({ method: "GET", url: "/readyz" })).statusCode, 200);
    app.markShuttingDown();
    assert.equal((await app.inject({ method: "GET", url: "/readyz" })).statusCode, 503);
  });
});

describe("metrics", () => {
  it("exposes pool gauges and route-templated latency", async () => {
    const app = buildApp({ config, pool: fakePool(true) });
    await app.inject({ method: "GET", url: "/healthz" });
    const res = await app.inject({ method: "GET", url: "/metrics" });
    assert.equal(res.statusCode, 200);
    assert.match(res.body, /db_pool_connections\{state="waiting"/);
    assert.match(res.body, /http_server_request_duration_seconds_bucket\{.*route="\/healthz"/);
  });
});

describe("request validation", () => {
  it("rejects a journal entry with missing fields before touching the database", async () => {
    const app = buildApp({ config, pool: fakePool(false) });
    const res = await app.inject({ method: "POST", url: "/v1/journal-entries", payload: { description: "x" } });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, "invalid_request");
  });
});
