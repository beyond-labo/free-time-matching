import { afterEach, describe, expect, it, vi } from "vitest";
import { exportPKCS8, generateKeyPair, jwtVerify } from "jose";
import { ApnsNotificationAdapter } from "../src/Notification/Infrastructure/Adapter/ApnsNotificationAdapter";
import { DeliverSchedulingNotifications } from "../src/Notification/Application/UseCase/DeliverSchedulingNotifications";
import { dispatchSchedulingNotifications } from "../src/Notification/Composition/Factory/dispatchSchedulingNotifications";
import { SupabaseNotificationDeliveryRepository } from "../src/Notification/Infrastructure/Repository/SupabaseNotificationDeliveryRepository";
import type { DeliveryOutcome, NotificationDelivery } from "../src/Notification/Domain/Model/NotificationDelivery";

const delivery: NotificationDelivery = {
  id: "00000000-0000-4000-8000-000000000001",
  token: "ab".repeat(32), environment: "sandbox", kind: "confirmed",
};
afterEach(() => vi.unstubAllGlobals());

describe("notification delivery", () => {
  it("signs APNs credentials and sends a generic alert with a stable collapse ID", async () => {
    const keys = await generateKeyPair("ES256", { extractable: true });
    const privateKey = await exportPKCS8(keys.privateKey);
    const requests: { url: string; init: RequestInit }[] = [];
    vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
      requests.push({ url, init });
      return new Response(null, { status: 200 });
    }));
    const adapter = new ApnsNotificationAdapter({ teamId: "TEAM", keyId: "KEY", privateKey, topic: "com.beyond-labo.aimano" });
    expect(await Promise.all([adapter.send(delivery), adapter.send({ ...delivery, environment: "production" })])).toEqual(["sent", "sent"]);
    expect(requests[0]!.url).toBe(`https://api.sandbox.push.apple.com/3/device/${delivery.token}`);
    expect(requests[1]!.url).toBe(`https://api.push.apple.com/3/device/${delivery.token}`);
    const headers = new Headers(requests[0]!.init.headers);
    expect(headers.get("apns-topic")).toBe("com.beyond-labo.aimano");
    expect(headers.get("apns-push-type")).toBe("alert");
    expect(headers.get("apns-collapse-id")).toBe(delivery.id);
    const token = headers.get("authorization")!.replace(/^bearer /, "");
    const verified = await jwtVerify(token, keys.publicKey, { issuer: "TEAM", algorithms: ["ES256"] });
    expect(verified.protectedHeader.kid).toBe("KEY");
    expect(verified.payload.iat).toBeTypeOf("number");
    expect(new Headers(requests[1]!.init.headers).get("authorization")).toBe(headers.get("authorization"));
    expect(JSON.parse(requests[0]!.init.body as string)).toEqual({
      aps: { alert: { title: "アイマノ", body: "予定が確定しました。アプリで確認してください。" }, sound: "default" },
    });
  });

  it("distinguishes invalid devices from transient APNs failures", async () => {
    const keys = await generateKeyPair("ES256", { extractable: true });
    const adapter = new ApnsNotificationAdapter({ teamId: "TEAM", keyId: "KEY", privateKey: await exportPKCS8(keys.privateKey), topic: "com.beyond-labo.aimano" });
    const responses = [
      new Response(null, { status: 410 }),
      new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 }),
      new Response(JSON.stringify({ reason: "DeviceTokenNotForTopic" }), { status: 400 }),
      new Response(null, { status: 429 }), new Response(null, { status: 503 }),
    ];
    vi.stubGlobal("fetch", vi.fn(async () => responses.shift()!));
    for (const expected of ["invalid_token", "invalid_token", "invalid_token", "retry", "retry"]) {
      expect(await adapter.send(delivery)).toBe(expected);
    }
  });

  it("acknowledges every leased delivery even when another delivery fails", async () => {
    const finishes: [string, DeliveryOutcome][] = [];
    const other = { ...delivery, id: "00000000-0000-4000-8000-000000000002" };
    const useCase = new DeliverSchedulingNotifications({
      claim: async () => [delivery, other],
      finish: async (id, outcome) => { finishes.push([id, outcome]); },
    }, { send: async (item) => {
      if (item.id === delivery.id) throw new Error("private transport details");
      return "sent";
    } });
    await expect(useCase.execute()).rejects.toThrow("notification_delivery_pending");
    expect(finishes).toContainEqual([delivery.id, "retry"]);
    expect(finishes).toContainEqual([other.id, "sent"]);
  });

  it("uses service-only RPC and rejects malformed delivery destinations", async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return new Response(JSON.stringify(url.endsWith("_claim") ? [delivery] : null));
    }));
    const repository = new SupabaseNotificationDeliveryRepository("https://db.example", "service-secret");
    expect(await repository.claim()).toEqual([delivery]);
    await repository.finish(delivery.id, "sent");
    expect(new Headers(calls[0]!.init.headers).get("authorization")).toBe("Bearer service-secret");
    expect(JSON.parse(calls[1]!.init.body as string)).toEqual({ p_id: delivery.id, p_outcome: "sent" });
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify([{ ...delivery, token: "../../arbitrary" }]))));
    await expect(repository.claim()).rejects.toThrow("invalid_notification_delivery");
  });

  it("leaves outbox untouched until credentials exist and rejects partial configuration", async () => {
    const network = vi.fn(); vi.stubGlobal("fetch", network);
    await dispatchSchedulingNotifications({});
    expect(network).not.toHaveBeenCalled();
    await expect(dispatchSchedulingNotifications({ APNS_TEAM_ID: "TEAM" })).rejects.toThrow("notification_configuration_incomplete");
    expect(network).not.toHaveBeenCalled();
  });
});
