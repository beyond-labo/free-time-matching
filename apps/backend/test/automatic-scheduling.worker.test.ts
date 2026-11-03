import { afterEach, describe, expect, it, vi } from "vitest";
import { createApp, type AppDependencies } from "../src/Composition/createApp";
import { InvalidAccessTokenError } from "../src/Auth/Application/Port/AccessTokenVerifier";
import { SchedulingConflictError, SchedulingUnavailableError, type SchedulingSnapshot } from "../src/AutomaticScheduling/Domain/Model/AutomaticScheduling";
import { SupabaseAutomaticSchedulingRepository, projectSchedulingSnapshot } from "../src/AutomaticScheduling/Infrastructure/Repository/SupabaseAutomaticSchedulingRepository";
import { runAutomaticSchedulingTick } from "../src/AutomaticScheduling/Infrastructure/Adapter/SupabaseSchedulingTickAdapter";
import { runScheduledTasks } from "../src/EntryPoint/index";

const actorId = "00000000-0000-4000-8000-000000000001";
const friendId = "00000000-0000-4000-8000-000000000002";
const proposalId = "00000000-0000-4000-8000-000000000003";
const operationId = "00000000-0000-4000-8000-000000000004";
const notificationId = "00000000-0000-4000-8000-000000000005";
const headers = { authorization: "Bearer valid-token", "content-type": "application/json" };
const base = "/v1/automatic-scheduling";
const snapshot: SchedulingSnapshot = { enabled: false, permissions: [], proposals: [], notifications: [] };
const rawProposal = {
  id: proposalId, start: "2030-01-01T19:00:00+00:00", end: "2030-01-01T20:00:00+00:00",
  status: "pending", myResponse: "pending", version: 1, shareAcceptance: false,
};
const peer = { userId: friendId, nickname: "友達", presetIconKey: "sun.max.fill" };
const repository = () => ({
  snapshot: vi.fn(async () => snapshot), settings: vi.fn(async () => snapshot),
  permission: vi.fn(async () => snapshot), respond: vi.fn(async () => snapshot),
  cancel: vi.fn(async () => snapshot), feedback: vi.fn(async () => snapshot),
  block: vi.fn(async () => snapshot), blockProposal: vi.fn(async () => snapshot),
  report: vi.fn(async () => snapshot), reportFriend: vi.fn(async () => snapshot),
  device: vi.fn(async () => snapshot),
});
const dependencies = (automaticScheduling: ReturnType<typeof repository> | SupabaseAutomaticSchedulingRepository): AppDependencies => ({
  tokenVerifier: { verify: async (token) => {
    if (token !== "valid-token") throw new InvalidAccessTokenError();
    return { id: actorId };
  } },
  manageProfile: { get: async () => null, put: async () => { throw new Error("unused"); } },
  manageFriendships: {
    snapshot: async () => { throw new Error("unused"); }, rotateCode: async () => { throw new Error("unused"); },
    resolveCode: async () => { throw new Error("unused"); }, sendRequest: async () => { throw new Error("unused"); },
    transitionRequest: async () => { throw new Error("unused"); }, removeFriend: async () => { throw new Error("unused"); },
  },
  requestDeletion: { execute: async () => { throw new Error("unused"); } },
  deletionStatus: { get: async () => null }, automaticScheduling,
});

afterEach(() => vi.unstubAllGlobals());

describe("automatic scheduling API", () => {
  it("authenticates private snapshots without a response envelope", async () => {
    const repo = repository();
    const app = createApp({}, dependencies(repo));
    expect((await app.request(base)).status).toBe(401);
    expect(repo.snapshot).not.toHaveBeenCalled();
    const response = await app.request(base, { headers });
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(await response.json()).toEqual(snapshot);
    expect(repo.snapshot).toHaveBeenCalledWith(actorId, "valid-token");
  });

  it("uses the JWT actor and preserves the response operation and disclosure choice", async () => {
    const repo = repository();
    const app = createApp({}, dependencies(repo));
    const input = { response: "accepted", shareAcceptance: false, operationId, expectedVersion: 1 };
    const response = await app.request(`${base}/proposals/${proposalId}/response`, {
      method: "PUT", headers, body: JSON.stringify({ ...input, actorId: friendId }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(snapshot);
    expect(repo.respond).toHaveBeenCalledWith(actorId, "valid-token", proposalId, input);
    for (const invalid of [
      { ...input, shareAcceptance: "false" }, { ...input, expectedVersion: 0 },
      { ...input, response: "pending" }, { ...input, response: "declined", shareAcceptance: true },
      { ...input, operationId: "invalid" },
    ]) {
      expect((await app.request(`${base}/proposals/${proposalId}/response`, {
        method: "PUT", headers, body: JSON.stringify(invalid),
      })).status).toBe(400);
    }
    expect(repo.respond).toHaveBeenCalledTimes(1);
  });

  it("forwards permission, cancellation, feedback and independent safety actions", async () => {
    const repo = repository();
    const app = createApp({}, dependencies(repo));
    const operation = { operationId };
    const examples = [
      { path: "/settings", method: "PUT", input: { enabled: true, operationId }, mock: repo.settings, args: [{ enabled: true, operationId }] },
      { path: `/permissions/${friendId}`, method: "PUT", input: { enabled: false, operationId }, mock: repo.permission, args: [friendId, { enabled: false, operationId }] },
      { path: `/proposals/${proposalId}/cancel`, method: "POST", input: { operationId, expectedVersion: 2 }, mock: repo.cancel, args: [proposalId, { operationId, expectedVersion: 2 }] },
      { path: `/proposals/${proposalId}/feedback`, method: "PUT", input: { operationId, played: true, bothersome: false, privacyConcern: false }, mock: repo.feedback, args: [proposalId, { operationId, played: true, bothersome: false, privacyConcern: false }] },
      { path: `/blocks/${friendId}`, method: "POST", input: operation, mock: repo.block, args: [friendId, operation] },
      { path: `/proposals/${proposalId}/block`, method: "POST", input: operation, mock: repo.blockProposal, args: [proposalId, operation] },
      { path: `/proposals/${proposalId}/report`, method: "POST", input: { operationId, reason: "spam" }, mock: repo.report, args: [proposalId, { operationId, reason: "spam" }] },
      { path: `/reports/${friendId}`, method: "POST", input: { operationId, reason: "harassment" }, mock: repo.reportFriend, args: [friendId, { operationId, reason: "harassment" }] },
    ];
    for (const example of examples) {
      const response = await app.request(base + example.path, { method: example.method, headers, body: JSON.stringify(example.input) });
      expect(response.status, example.path).toBe(200);
      expect(example.mock).toHaveBeenCalledWith(actorId, "valid-token", ...example.args);
    }
    expect(repo.report).toHaveBeenCalledTimes(1);
    expect(repo.block).toHaveBeenCalledTimes(1);
    expect(repo.blockProposal).toHaveBeenCalledTimes(1);
  });

  it("validates device registration and normalizes the token without trusting an owner ID", async () => {
    const repo = repository();
    const app = createApp({}, dependencies(repo));
    const token = "AB".repeat(32);
    const response = await app.request(`${base}/device`, { method: "PUT", headers,
      body: JSON.stringify({ token, environment: "sandbox", enabled: false, actorId: friendId }) });
    expect(response.status).toBe(200);
    expect(repo.device).toHaveBeenCalledWith(actorId, "valid-token", { token: token.toLowerCase(), environment: "sandbox", enabled: false });
    expect((await app.request(`${base}/device`, { method: "PUT", headers,
      body: JSON.stringify({ token: "invalid", environment: "sandbox", enabled: true }) })).status).toBe(400);
    expect((await app.request(`${base}/settings`, { method: "PUT", headers, body: "{" })).status).toBe(400);
    expect((await app.request(`${base}/permissions/not-uuid`, { method: "PUT", headers,
      body: JSON.stringify({ enabled: true, operationId }) })).status).toBe(400);
  });

  it("keeps conflicts, inaccessible records and dependency failures distinct without exposing details", async () => {
    const repo = repository();
    const app = createApp({}, dependencies(repo));
    for (const [error, expected, code] of [
      [new SchedulingConflictError(), 409, "automatic_scheduling_conflict"],
      [new SchedulingUnavailableError(), 404, "automatic_scheduling_unavailable"],
      [new Error("secret database response"), 503, "service_unavailable"],
    ] as const) {
      repo.cancel.mockRejectedValueOnce(error);
      const response = await app.request(`${base}/proposals/${proposalId}/cancel`, {
        method: "POST", headers, body: JSON.stringify({ operationId, expectedVersion: 1 }),
      });
      expect(response.status).toBe(expected);
      const body = await response.text();
      expect(JSON.parse(body).error.code).toBe(code);
      expect(body).not.toContain("secret database response");
      expect(response.headers.get("cache-control")).toBe("private, no-store");
    }
  });
});

describe("Supabase automatic scheduling projection", () => {
  it("removes raw peer and slot fields from an anonymous proposal", () => {
    const projected = projectSchedulingSnapshot({ ...snapshot, secret: "hidden",
      proposals: [{ ...rawProposal, peer, rawSlots: ["private"], peerResponse: "declined", reason: "private" }] });
    expect(projected).toEqual({ ...snapshot, proposals: [{ ...rawProposal,
      start: "2030-01-01T19:00:00.000Z", end: "2030-01-01T20:00:00.000Z" }] });
  });

  it("shows an explicitly shared accepted peer or a confirmed plan, keeping other extra fields out", () => {
    for (const status of ["pending", "confirmed"]) {
      const projected = projectSchedulingSnapshot({ ...snapshot,
        proposals: [{ ...rawProposal, status, myResponse: "accepted", peer: { ...peer, availability: ["private"] }, peerResponse: "accepted" }],
        notifications: [{ id: notificationId, proposalId, kind: "confirmed", createdAt: "2030-01-01T18:00:00Z", peerId: friendId }],
      });
      expect(projected.proposals[0].peer).toEqual(peer);
      expect(projected.proposals[0].peerResponse).toBe("accepted");
      expect(JSON.stringify(projected)).not.toContain("availability");
      expect(JSON.stringify(projected)).not.toContain("peerId");
    }
  });

  it("keeps completed plans and feedback readable after the peer retires", () => {
    for (const retiredPeer of [undefined, null]) {
      const projected = projectSchedulingSnapshot({ ...snapshot, proposals: [{
        ...rawProposal, status: "confirmed", myResponse: "accepted", peer: retiredPeer,
        feedback: { played: true, bothersome: false, privacyConcern: false },
      }] });
      expect(projected.proposals[0].status).toBe("confirmed");
      expect(projected.proposals[0].peer).toBeUndefined();
      expect(projected.proposals[0].peerResponse).toBeUndefined();
      expect(projected.proposals[0].feedback?.played).toBe(true);
    }
    expect(() => projectSchedulingSnapshot({ ...snapshot, proposals: [{
      ...rawProposal, status: "confirmed", myResponse: "accepted", peer: { ...peer, userId: "invalid" },
    }] })).toThrow();
  });

  it("serves the snapshot with past confirmed plans when the peer is no longer present", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ ...snapshot, proposals: [{
      ...rawProposal, start: "2020-01-01T19:00:00Z", end: "2020-01-01T20:00:00Z",
      status: "confirmed", myResponse: "accepted", peer: null,
    }] }))));
    const adapter = new SupabaseAutomaticSchedulingRepository({ url: "https://supabase.example", apiKey: "publishable-key" });
    const response = await createApp({}, dependencies(adapter)).request(base, { headers });
    expect(response.status).toBe(200);
    const result = await response.json() as SchedulingSnapshot;
    expect(result.proposals[0].status).toBe("confirmed");
    expect(result.proposals[0].peer).toBeUndefined();
  });

  it("rejects malformed projection dates, versions, enum values, interval length and shared-peer shape", () => {
    for (const change of [
      { status: "made-up" }, { version: 0 }, { start: "not-a-date" },
      { end: "2030-01-03T20:00:00Z" }, { start: "2030-01-01T19:01:00Z" },
      { peerResponse: "accepted", peer: null },
    ]) {
      expect(() => projectSchedulingSnapshot({ ...snapshot, proposals: [{ ...rawProposal, ...change }] })).toThrow();
    }
  });

  it("passes only the user token and explicit RPC parameters for every mutation", async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => new Response(JSON.stringify(snapshot), { status: 200 }));
    vi.stubGlobal("fetch", fetcher);
    const adapter = new SupabaseAutomaticSchedulingRepository({ url: "https://supabase.example", apiKey: "publishable-key" });
    await adapter.settings(actorId, "user-token", { enabled: true, operationId });
    expect(fetcher.mock.calls[0]?.[0]).toBe("https://supabase.example/rest/v1/rpc/automatic_scheduling_settings");
    const init = fetcher.mock.calls[0]?.[1] as RequestInit;
    expect(new Headers(init.headers).get("authorization")).toBe("Bearer user-token");
    expect(new Headers(init.headers).get("apikey")).toBe("publishable-key");
    expect(JSON.parse(init.body as string)).toEqual({ p_enabled: true, p_operation_id: operationId });
    await adapter.respond(actorId, "user-token", proposalId, { response: "accepted", shareAcceptance: true, expectedVersion: 1, operationId });
    expect(JSON.parse((fetcher.mock.calls[1]?.[1] as RequestInit).body as string)).toEqual({
      p_proposal_id: proposalId, p_response: "accepted", p_share_acceptance: true, p_expected_version: 1, p_operation_id: operationId,
    });
    await adapter.blockProposal(actorId, "user-token", proposalId, { operationId });
    expect(fetcher.mock.calls[2]?.[0]).toContain("automatic_scheduling_block_proposal");
    await adapter.reportFriend(actorId, "user-token", friendId, { reason: "other", operationId });
    expect(JSON.parse((fetcher.mock.calls[3]?.[1] as RequestInit).body as string)).toEqual({ p_friend_id: friendId, p_reason: "other", p_operation_id: operationId });
  });

  it("maps SQL permission/input/conflict failures to stable HTTP errors without returning SQL messages", async () => {
    const repo = new SupabaseAutomaticSchedulingRepository({ url: "https://supabase.example", apiKey: "publishable-key" });
    const app = createApp({}, dependencies(repo));
    for (const [code, message, expected] of [
      ["23514", "scheduling_invalid", 400], ["42501", "scheduling_unavailable", 404],
      ["23505", "scheduling_conflict", 409], ["40001", "scheduling_conflict", 409],
      ["XX000", "sensitive SQL body", 503],
    ] as const) {
      vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ code, message }), { status: 400 })));
      const response = await app.request(base, { headers });
      expect(response.status).toBe(expected);
      expect(await response.text()).not.toContain("sensitive SQL body");
    }
  });
});

describe("automatic scheduling background job", () => {
  it("calls the service-only tick with privileged credentials and validates the result", async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => new Response("1", { status: 200 }));
    vi.stubGlobal("fetch", fetcher);
    await runAutomaticSchedulingTick({ SUPABASE_URL: "https://supabase.example", SUPABASE_SECRET_KEY: "service-secret" });
    const [url, init] = fetcher.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://supabase.example/rest/v1/rpc/automatic_scheduling_tick");
    expect(new Headers(init.headers).get("authorization")).toBe("Bearer service-secret");
    expect(new Headers(init.headers).get("apikey")).toBe("service-secret");
    await expect(runAutomaticSchedulingTick({})).rejects.toThrow("configuration");
    vi.stubGlobal("fetch", vi.fn(async () => new Response("null", { status: 200 })));
    await expect(runAutomaticSchedulingTick({ SUPABASE_URL: "https://supabase.example", SUPABASE_SECRET_KEY: "service-secret" })).rejects.toThrow("Invalid scheduling job result");
  });

  it("dispatches after matching and still attempts existing notifications after a matching failure", async () => {
    const order: string[] = [];
    await runScheduledTasks({}, async () => { order.push("tick"); }, async () => { order.push("dispatch"); });
    expect(order).toEqual(["tick", "dispatch"]);
    const dispatch = vi.fn(async () => {});
    await expect(runScheduledTasks({}, async () => { throw new Error("private SQL"); }, dispatch)).rejects.toThrow("Scheduled automatic scheduling failed.");
    expect(dispatch).toHaveBeenCalledTimes(1);
    await expect(runScheduledTasks({}, async () => {}, async () => { throw new Error("private device token"); })).rejects.toThrow("Scheduled automatic scheduling failed.");
  });
});
