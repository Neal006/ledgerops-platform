import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { type JournalInput, LedgerError, requestHash, validateJournal } from "../src/ledger.js";

const base = (postings: JournalInput["postings"]): JournalInput => ({
  idempotency_key: "test-key-0001",
  description: "client deposit",
  occurred_at: "2026-10-01T10:00:00Z",
  postings,
});

function expectLedgerError(fn: () => void, code: string) {
  assert.throws(fn, (err: unknown) => err instanceof LedgerError && err.code === code);
}

describe("validateJournal", () => {
  it("accepts a balanced two-leg entry", () => {
    validateJournal(
      base([
        { account_code: "BROKER:ALPACA:USD", amount_minor: "150000", currency: "USD" },
        { account_code: "CLIENT:42:USD", amount_minor: "-150000", currency: "USD" },
      ]),
    );
  });

  it("accepts multi-currency entries balanced per currency", () => {
    validateJournal(
      base([
        { account_code: "FX:USD", amount_minor: "1000", currency: "USD" },
        { account_code: "CLIENT:1:USD", amount_minor: "-1000", currency: "USD" },
        { account_code: "FX:AED", amount_minor: "3673", currency: "AED" },
        { account_code: "CLIENT:1:AED", amount_minor: "-3673", currency: "AED" },
      ]),
    );
  });

  it("rejects an unbalanced entry", () => {
    expectLedgerError(
      () =>
        validateJournal(
          base([
            { account_code: "A", amount_minor: "100", currency: "USD" },
            { account_code: "B", amount_minor: "-99", currency: "USD" },
          ]),
        ),
      "unbalanced",
    );
  });

  it("rejects entries that only balance across currencies", () => {
    expectLedgerError(
      () =>
        validateJournal(
          base([
            { account_code: "A", amount_minor: "100", currency: "USD" },
            { account_code: "B", amount_minor: "-100", currency: "AED" },
          ]),
        ),
      "unbalanced",
    );
  });

  it("rejects a single posting", () => {
    expectLedgerError(
      () => validateJournal(base([{ account_code: "A", amount_minor: "100", currency: "USD" }])),
      "too_few_postings",
    );
  });

  for (const bad of ["0", "1.5", "abc", "", "007", "1e3"]) {
    it(`rejects malformed amount "${bad}"`, () => {
      expectLedgerError(
        () =>
          validateJournal(
            base([
              { account_code: "A", amount_minor: bad, currency: "USD" },
              { account_code: "B", amount_minor: "-1", currency: "USD" },
            ]),
          ),
        "invalid_amount",
      );
    });
  }

  it("handles amounts beyond Number.MAX_SAFE_INTEGER without precision loss", () => {
    validateJournal(
      base([
        { account_code: "A", amount_minor: "900719925474099300", currency: "USD" },
        { account_code: "B", amount_minor: "-900719925474099300", currency: "USD" },
      ]),
    );
  });
});

describe("requestHash", () => {
  it("is independent of posting order", () => {
    const a = base([
      { account_code: "A", amount_minor: "5", currency: "USD" },
      { account_code: "B", amount_minor: "-5", currency: "USD" },
    ]);
    const b = { ...a, postings: [...a.postings].reverse() };
    assert.equal(requestHash(a), requestHash(b));
  });

  it("changes when an amount changes", () => {
    const a = base([
      { account_code: "A", amount_minor: "5", currency: "USD" },
      { account_code: "B", amount_minor: "-5", currency: "USD" },
    ]);
    const b = base([
      { account_code: "A", amount_minor: "6", currency: "USD" },
      { account_code: "B", amount_minor: "-6", currency: "USD" },
    ]);
    assert.notEqual(requestHash(a), requestHash(b));
  });
});
