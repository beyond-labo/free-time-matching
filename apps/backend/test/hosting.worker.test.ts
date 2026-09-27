import { describe, expect, it, vi } from "vitest";
import { createApp, type AppDependencies } from "../src/Composition/createApp";
import { InvalidAccessTokenError } from "../src/Auth/Application/Port/AccessTokenVerifier";
import type { HostingRepository } from "../src/Hosting/Application/Port/HostingRepository";
import { HostingConflictError, type CreateHostingInput, type HostingProjection, type HostingResponseInput } from "../src/Hosting/Domain/Hosting";
import { SupabaseHostingRepository } from "../src/Hosting/Infrastructure/Repository/SupabaseHostingRepository";

const hostId = "00000000-0000-4000-8000-000000000001";
const friendId = "00000000-0000-4000-8000-000000000002";
const hostingId = "00000000-0000-4000-8000-000000000003";
const operationId = "00000000-0000-4000-8000-000000000004";
const headers = { authorization: "Bearer valid-token", "content-type": "application/json" };
const start = new Date(Math.ceil(Date.now() / 900000) * 900000 + 900000).toISOString();
const end = new Date(Date.parse(start) + 3600000).toISOString();

const hostProjection: HostingProjection = {
  id: hostingId, start, end, mode: "online", area: null, category: "game", status: "open", version: 1,
  acceptedParticipants: [],
};
const inviteeProjection: HostingProjection = {
  id: hostingId, start, end, mode: "online", area: null, category: "game", status: "open", version: 1,
  host: { userId: hostId, nickname: "ホスト", presetIconKey: "sun.max.fill" },
  myInvitation: { status: "pending", version: 1, intervals: null },
};
const dependencies = (hosting: HostingRepository, actorId = hostId): AppDependencies => ({
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
  deletionStatus: { get: async () => null },
  hosting,
});

describe("/v1/hostings", () => {
  it("passes typed friend targets and availability metadata to atomic creation", async () => {
    let saved: CreateHostingInput | undefined;
    const repository: HostingRepository = {
      create: async (_actor, _token, input) => { saved = input; return hostProjection; },
      list: async () => [], get: async () => null,
      respond: async () => { throw new Error("unused"); }, cancel: async () => { throw new Error("unused"); },
    };
    const app = createApp({}, dependencies(repository));
    const response = await app.request("/v1/hostings", { method: "POST", headers, body: JSON.stringify({
      start, end, mode: "online", category: "game", targets: [{ type: "friend", id: friendId }],
      availabilityMetadata: { category: "meal", visibility: "privateUntilAccepted" }, operationId,
    }) });
    expect(response.status).toBe(201);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(saved).toEqual({ start, end, mode: "online", area: null, category: "game",
      targets: [{ type: "friend", id: friendId }], availabilityMetadata: { category: "meal", visibility: "privateUntilAccepted" }, operationId });
    expect(await response.json()).toEqual({ hosting: hostProjection });
    const invalid = await app.request("/v1/hostings", { method: "POST", headers, body: JSON.stringify({
      start, end, mode: "online", targets: [{ type: "group", id: friendId }],
      availabilityMetadata: { visibility: "privateUntilAccepted" }, operationId,
    }) });
    expect(invalid.status).toBe(400);
  });

  it("returns only the repository's role projection and forwards partial replies", async () => {
    let answered: HostingResponseInput | undefined;
    const repository: HostingRepository = {
      create: async () => { throw new Error("unused"); },
      list: async () => [inviteeProjection], get: async () => inviteeProjection,
      respond: async (_actor, _token, _id, input) => { answered = input; return {
        ...inviteeProjection, myInvitation: { status: "accepted", version: 2, intervals: input.intervals },
      }; }, cancel: async () => { throw new Error("unused"); },
    };
    const app = createApp({}, dependencies(repository, friendId));
    const listed = await app.request("/v1/hostings", { headers });
    expect(listed.status).toBe(200);
    expect((await listed.json() as { hostings: HostingProjection[] }).hostings[0]).toEqual(inviteeProjection);
    const partialEnd = new Date(Date.parse(start) + 1800000).toISOString();
    const response = await app.request(`/v1/hostings/${hostingId}/response`, { method: "PUT", headers, body: JSON.stringify({
      status: "accepted", intervals: [{ start, end: partialEnd }], operationId, expectedVersion: 1,
    }) });
    expect(response.status).toBe(200);
    expect(answered).toEqual({ status: "accepted", intervals: [{ start, end: partialEnd }], operationId, expectedVersion: 1 });
    expect((await response.json() as { hosting: HostingProjection }).hosting.myInvitation?.status).toBe("accepted");
  });

  it("rejects unauthenticated mutation and reports stale version", async () => {
    const repository: HostingRepository = {
      create: async () => { throw new Error("unused"); }, list: async () => [], get: async () => null,
      respond: async () => { throw new Error("unused"); }, cancel: async () => { throw new HostingConflictError(); },
    };
    const app = createApp({}, dependencies(repository));
    expect((await app.request("/v1/hostings")).status).toBe(401);
    const response = await app.request(`/v1/hostings/${hostingId}/cancel`, { method: "POST", headers,
      body: JSON.stringify({ operationId, expectedVersion: 1 }) });
    expect(response.status).toBe(409);
    expect((await response.json() as { error: { code: string } }).error.code).toBe("hosting_conflict");
  });

  it("maps a database input constraint to 400 while keeping permission failures private", async () => {
    const repository = new SupabaseHostingRepository({ url: "https://supabase.example", apiKey: "test-key" });
    const app = createApp({}, dependencies(repository));
    const body = JSON.stringify({ start, end, mode: "online", targets: [{ type: "friend", id: friendId }],
      availabilityMetadata: { category: null, visibility: "privateUntilAccepted" }, operationId });
    try {
      vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ code: "23514", message: "hosting_unavailable" }), { status: 400 })));
      const invalid = await app.request("/v1/hostings", { method: "POST", headers, body });
      expect(invalid.status).toBe(400);
      expect((await invalid.json() as { error: { code: string } }).error.code).toBe("hosting_invalid");
      vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ code: "42501", message: "hosting_unavailable" }), { status: 403 })));
      const hidden = await app.request("/v1/hostings", { method: "POST", headers, body });
      expect(hidden.status).toBe(404);
    } finally { vi.unstubAllGlobals(); }
  });
});
