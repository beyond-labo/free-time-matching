import { describe, expect, it } from "vitest";
import type { AccessTokenVerifier } from "../src/Auth/Application/Port/AccessTokenVerifier";
import { createApp, type AppDependencies } from "../src/Composition/createApp";
import type { AvailabilityRepository } from "../src/Availability/Application/Port/AvailabilityRepository";
import { AvailabilityConflictError, type AvailabilityInput, type AvailabilitySlot } from "../src/Availability/Domain/Model/Availability";
import type { AccountDeletionStatusPort } from "../src/AccountDeletion/Application/Port/AccountDeletionPorts";
import { InvalidAccessTokenError } from "../src/Auth/Application/Port/AccessTokenVerifier";

const userId = "8e26166a-a14a-4933-a953-199798829ab5";
const slotId = "8e26166a-a14a-4933-a953-199798829ab6";

class MemoryAvailabilityRepository implements AvailabilityRepository {
  slots: AvailabilitySlot[] = [];
  async list(): Promise<AvailabilitySlot[]> { return this.slots; }
  async upsert(_actorId: string, _token: string, id: string, input: AvailabilityInput): Promise<AvailabilitySlot> {
    const existing = this.slots.find((item) => item.id === id);
    if (existing) {
      if (JSON.stringify(existing) !== JSON.stringify({ id, ...input })) throw new AvailabilityConflictError();
      return existing;
    }
    const slot = { id, ...input };
    this.slots = [...this.slots.filter((item) => item.id !== id), slot];
    return slot;
  }
  async remove(_actorId: string, _token: string, id: string): Promise<void> {
    this.slots = this.slots.filter((item) => item.id !== id);
  }
}

const buildApp = (availability: AvailabilityRepository) => {
  const tokenVerifier: AccessTokenVerifier = {
    verify: async (token) => {
      if (token !== "valid-token") throw new InvalidAccessTokenError();
      return { id: userId };
    },
  };
  const dependencies: AppDependencies = {
    tokenVerifier,
    manageProfile: { get: async () => null, put: async () => { throw new Error("unused"); } },
    manageFriendships: {
      snapshot: async () => { throw new Error("unused"); }, rotateCode: async () => { throw new Error("unused"); },
      resolveCode: async () => { throw new Error("unused"); }, sendRequest: async () => { throw new Error("unused"); },
      transitionRequest: async () => { throw new Error("unused"); }, removeFriend: async () => { throw new Error("unused"); },
    },
    requestDeletion: { execute: async () => { throw new Error("unused"); } },
    deletionStatus: { get: async () => null } satisfies AccountDeletionStatusPort,
    availability,
  };
  return createApp({}, dependencies);
};

describe("/v1/availability", () => {
  it("lists, upserts, and deletes only through the authenticated route", async () => {
    const repository = new MemoryAvailabilityRepository();
    const app = buildApp(repository);
    const start = new Date(Math.ceil(Date.now() / 900000) * 900000 + 900000).toISOString();
    const end = new Date(Date.parse(start) + 3600000).toISOString();
    const headers = { authorization: "Bearer valid-token", "content-type": "application/json" };
    const saved = await app.request(`/v1/availability/${slotId}`, {
      method: "PUT", headers, body: JSON.stringify({ start, end, category: "game", visibility: "privateUntilAccepted" }),
    });
    expect(saved.status).toBe(200);
    expect(await saved.json()).toEqual({ slot: { id: slotId, start, end, category: "game", visibility: "privateUntilAccepted" } });
    const replay = await app.request(`/v1/availability/${slotId}`, {
      method: "PUT", headers, body: JSON.stringify({ start, end, category: "game", visibility: "privateUntilAccepted" }),
    });
    expect(replay.status).toBe(200);
    const changed = await app.request(`/v1/availability/${slotId}`, {
      method: "PUT", headers, body: JSON.stringify({ start, end, category: "meal", visibility: "privateUntilAccepted" }),
    });
    expect(changed.status).toBe(409);
    const listed = await app.request("/v1/availability", { headers });
    expect(listed.headers.get("cache-control")).toBe("private, no-store");
    expect(listed.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/i);
    expect(await listed.json()).toEqual({ slots: repository.slots });
    expect((await app.request(`/v1/availability/${slotId}`, { method: "DELETE", headers })).status).toBe(204);
  });

  it("rejects invalid category and unauthenticated requests", async () => {
    const app = buildApp(new MemoryAvailabilityRepository());
    const unauthorized = await app.request("/v1/availability");
    expect(unauthorized.status).toBe(401);
    expect((await app.request("/v1/availability", { headers: { authorization: "Bearer invalid-token" } })).status).toBe(401);
    const start = new Date(Math.ceil(Date.now() / 900000) * 900000 + 900000).toISOString();
    const response = await app.request(`/v1/availability/${slotId}`, {
      method: "PUT", headers: { authorization: "Bearer valid-token", "content-type": "application/json" },
      body: JSON.stringify({ start, end: new Date(Date.parse(start) + 900000).toISOString(), category: "invalid", visibility: "privateUntilAccepted" }),
    });
    expect(response.status).toBe(400);
  });
});
