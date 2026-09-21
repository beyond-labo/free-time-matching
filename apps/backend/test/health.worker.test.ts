import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

describe("GET /healthz", () => {
  it("returns the stable public health contract", async () => {
    const response = await exports.default.fetch(
      new Request("https://example.com/healthz"),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("application/json");
    expect(await response.text()).toBe('{"status":"ok"}');
    expect(response.headers.get("x-runtime-binding")).toBeNull();
  });

  it("does not expose internal information in the health payload", async () => {
    const response = await exports.default.fetch(
      new Request("https://example.com/healthz"),
    );
    const body = await response.json();

    expect(body).toEqual({ status: "ok" });
    expect(JSON.stringify(body)).not.toMatch(
      /binding|environment|env|secret|stack|trace|runtime/i,
    );
  });

  it("returns 404 for an undefined route", async () => {
    const response = await exports.default.fetch(
      new Request("https://example.com/not-defined"),
    );

    expect(response.status).toBe(404);
  });
});
