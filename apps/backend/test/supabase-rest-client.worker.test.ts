import { afterEach, describe, expect, it, vi } from "vitest";
import { supabaseFetch } from "../src/Shared/Infrastructure/SupabaseRestClient";
import { runAutomaticSchedulingTick } from "../src/AutomaticScheduling/Infrastructure/Adapter/SupabaseSchedulingTickAdapter";
import { SupabaseNotificationDeliveryRepository } from "../src/Notification/Infrastructure/Repository/SupabaseNotificationDeliveryRepository";

afterEach(() => vi.unstubAllGlobals());
describe("Supabase authentication headers", () => {
  it("uses secret keys only as apikey for scheduled matching and notification RPCs", async () => {
    const calls: Headers[] = [];
    vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
      calls.push(new Headers(init.headers));
      return new Response(JSON.stringify(url.endsWith("_tick") ? 0 : []));
    }));
    await runAutomaticSchedulingTick({ SUPABASE_URL: "https://db.example", SUPABASE_SECRET_KEY: "sb_secret_test-only" });
    await new SupabaseNotificationDeliveryRepository("https://db.example", "sb_secret_test-only").claim();
    expect(calls).toHaveLength(2);
    for (const headers of calls) {
      expect(headers.get("apikey")).toBe("sb_secret_test-only");
      expect(headers.has("authorization")).toBe(false);
    }
  });
  it("preserves the actual user JWT with publishable keys", async () => {
    let headers = new Headers();
    vi.stubGlobal("fetch", vi.fn(async (_url: string, init: RequestInit) => {
      headers = new Headers(init.headers); return new Response("{}");
    }));
    await supabaseFetch({ url: "https://db.example", apiKey: "sb_publishable_test-only" }, "/rest/v1/rpc/example", { method: "POST", body: "{}" }, "user-access-jwt");
    expect(headers.get("apikey")).toBe("sb_publishable_test-only");
    expect(headers.get("authorization")).toBe("Bearer user-access-jwt");
  });
  it("keeps legacy service-role JWTs compatible", async () => {
    let headers = new Headers();
    vi.stubGlobal("fetch", vi.fn(async (_url: string, init: RequestInit) => {
      headers = new Headers(init.headers); return new Response("{}");
    }));
    await supabaseFetch({ url: "https://db.example", apiKey: "eyJ.legacy-jwt.signature" }, "/rest/v1/rpc/example", { method: "POST" });
    expect(headers.get("authorization")).toBe("Bearer eyJ.legacy-jwt.signature");
  });
});
