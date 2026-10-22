import type { FastifyInstance } from "fastify";
import { type JournalInput, type Ledger, LedgerError, type NewAccount } from "./ledger.js";

const accountBody = {
  type: "object",
  required: ["code", "name", "type", "currency"],
  additionalProperties: false,
  properties: {
    code: { type: "string", pattern: "^[A-Z0-9][A-Z0-9:_-]{1,63}$" },
    name: { type: "string", minLength: 1, maxLength: 200 },
    type: { type: "string", enum: ["asset", "liability", "equity", "revenue", "expense"] },
    currency: { type: "string", pattern: "^[A-Z]{3}$" },
  },
} as const;

const journalBody = {
  type: "object",
  required: ["idempotency_key", "description", "occurred_at", "postings"],
  additionalProperties: false,
  properties: {
    idempotency_key: { type: "string", minLength: 8, maxLength: 128 },
    description: { type: "string", minLength: 1, maxLength: 500 },
    occurred_at: { type: "string", format: "date-time" },
    external_ref: { type: "string", maxLength: 128 },
    postings: {
      type: "array",
      minItems: 2,
      maxItems: 50,
      items: {
        type: "object",
        required: ["account_code", "amount_minor", "currency"],
        additionalProperties: false,
        properties: {
          account_code: { type: "string" },
          amount_minor: { type: "string" },
          currency: { type: "string", pattern: "^[A-Z]{3}$" },
        },
      },
    },
  },
} as const;

export function registerLedgerRoutes(app: FastifyInstance, ledger: Ledger): void {
  app.setErrorHandler((err, req, reply) => {
    if (err instanceof LedgerError) {
      return reply.code(err.statusCode).send({ error: err.code, message: err.message });
    }
    const validation = (err as { validation?: unknown }).validation;
    if (validation) {
      return reply.code(400).send({ error: "invalid_request", message: (err as Error).message });
    }
    req.log.error({ err }, "unhandled error");
    return reply.code(500).send({ error: "internal_error", message: "internal error" });
  });

  app.post<{ Body: NewAccount }>("/v1/accounts", { schema: { body: accountBody } }, async (req, reply) => {
    const account = await ledger.createAccount(req.body);
    return reply.code(201).send(account);
  });

  app.get("/v1/accounts/balances", async () => ({ balances: await ledger.listBalances() }));

  app.get<{ Params: { code: string } }>("/v1/accounts/:code/balance", async (req) => ledger.getBalance(req.params.code));

  app.post<{ Body: JournalInput }>("/v1/journal-entries", { schema: { body: journalBody } }, async (req, reply) => {
    const result = await ledger.postJournal(req.body);
    return reply.code(result.replayed ? 200 : 201).send(result);
  });
}
