import assert from "node:assert/strict";
import test from "node:test";

import { buildHealthUrl, runHealthSmoke } from "./smoke-health.mjs";

test("buildHealthUrl appends healthz and removes query and fragment", () => {
  assert.equal(
    buildHealthUrl("https://api-staging.beyond-labo.com/base/?debug=1#fragment").href,
    "https://api-staging.beyond-labo.com/base/healthz",
  );
});

test("runHealthSmoke retries a transient failure and then succeeds", async () => {
  let requests = 0;
  let sleeps = 0;
  const logs = [];

  await runHealthSmoke({
    baseUrl: "https://api-staging.beyond-labo.com",
    timeoutMs: 100,
    maxAttempts: 3,
    retryDelayMs: 1,
    fetchImpl: async () => {
      requests += 1;
      return requests === 1
        ? new Response("temporarily unavailable", { status: 503 })
        : Response.json({ status: "ok" });
    },
    sleep: async () => {
      sleeps += 1;
    },
    logger: {
      log: (message) => logs.push(message),
      warn: (message) => logs.push(message),
    },
  });

  assert.equal(requests, 2);
  assert.equal(sleeps, 1);
  assert.match(logs.at(-1), /passed on attempt 2\/3/);
});

test("runHealthSmoke fails after the configured attempt limit", async () => {
  let requests = 0;

  await assert.rejects(
    runHealthSmoke({
      baseUrl: "https://api.beyond-labo.com",
      timeoutMs: 100,
      maxAttempts: 2,
      retryDelayMs: 1,
      fetchImpl: async () => {
        requests += 1;
        throw new TypeError("DNS is not ready");
      },
      sleep: async () => {},
      logger: { log: () => {}, warn: () => {} },
    }),
    /could not be reached after 2 attempts/,
  );

  assert.equal(requests, 2);
});
