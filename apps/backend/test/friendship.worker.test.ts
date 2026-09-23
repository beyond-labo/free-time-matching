import { describe, expect, it } from "vitest";
import type { AccessTokenVerifier } from "../src/Auth/Application/Port/AccessTokenVerifier";
import type { AccountDeletionStatusPort } from "../src/AccountDeletion/Application/Port/AccountDeletionPorts";
import { createApp, type AppDependencies } from "../src/Composition/createApp";
import type { FriendshipRepository, NewInviteCode } from "../src/Friendship/Application/Port/FriendshipRepository";
import {
  ManageFriendships,
  type FriendshipCodeGenerator,
} from "../src/Friendship/Application/UseCase/ManageFriendships";
import {
  FriendshipConflictError,
  InviteCodeUnavailableError,
  type FriendProfile,
  type FriendRequestTransition,
  type FriendshipSnapshot,
} from "../src/Friendship/Domain/Model/Friendship";
import { ManageProfile } from "../src/User/Application/UseCase/ManageProfile";

const himariId = "00000000-0000-4000-8000-000000000001";
const rikuId = "00000000-0000-4000-8000-000000000002";
const requestId = "00000000-0000-4000-8000-000000000010";
const operationId = "00000000-0000-4000-8000-000000000020";
const code = "HIMA-ABCD-EFGH-JKMP-QRST";

const profiles: Record<string, FriendProfile> = {
  [himariId]: { userId: himariId, nickname: "ひまり", presetIconKey: "sun.max.fill" },
  [rikuId]: { userId: rikuId, nickname: "りく", presetIconKey: "figure.run" },
};

class FixedCodeGenerator implements FriendshipCodeGenerator {
  async generate(): Promise<NewInviteCode> {
    return { value: code, hash: `hash:${code}`, expiresAt: "2026-09-30T00:00:00.000Z" };
  }

  async hash(value: string): Promise<string> {
    return `hash:${value.trim().toUpperCase()}`;
  }
}

class MemoryFriendshipRepository implements FriendshipRepository {
  codes = new Map<string, NewInviteCode>();
  requests: Array<{
    id: string;
    requesterId: string;
    addresseeId: string;
    version: number;
    status: "pending" | "accepted" | "rejected" | "cancelled";
    operationId: string;
  }> = [];
  friendships = new Map<string, { version: number; operationId: string }>();

  async snapshot(actorId: string): Promise<FriendshipSnapshot> {
    const relation = [...this.friendships.entries()].flatMap(([pair, value]) => {
      const ids = pair.split(":");
      if (!ids.includes(actorId)) return [];
      const otherId = ids[0] === actorId ? ids[1] : ids[0];
      return [{ profile: profiles[otherId]!, version: value.version, createdAt: "2026-09-23T00:00:00.000Z" }];
    });
    const request = (row: typeof this.requests[number], otherId: string) => ({
      id: row.id,
      profile: profiles[otherId]!,
      version: row.version,
      createdAt: "2026-09-23T00:00:00.000Z",
    });
    return {
      inviteCode: this.codes.get(actorId)
        ? { value: this.codes.get(actorId)!.value, expiresAt: this.codes.get(actorId)!.expiresAt }
        : null,
      friends: relation,
      incomingRequests: this.requests
        .filter((row) => row.status === "pending" && row.addresseeId === actorId)
        .map((row) => request(row, row.requesterId)),
      outgoingRequests: this.requests
        .filter((row) => row.status === "pending" && row.requesterId === actorId)
        .map((row) => request(row, row.addresseeId)),
    };
  }

  async rotateCode(actorId: string, _token: string, next: NewInviteCode): Promise<FriendshipSnapshot> {
    this.codes.set(actorId, next);
    return this.snapshot(actorId);
  }

  async ensureCode(actorId: string, _token: string, next: NewInviteCode): Promise<FriendshipSnapshot> {
    if (!this.codes.has(actorId)) this.codes.set(actorId, next);
    return this.snapshot(actorId);
  }

  async resolveCode(actorId: string, _token: string, hash: string): Promise<FriendProfile> {
    const owner = [...this.codes.entries()].find(([, value]) => value.hash === hash)?.[0];
    if (!owner || owner === actorId) throw new InviteCodeUnavailableError();
    return profiles[owner]!;
  }

  async sendRequest(
    actorId: string,
    _token: string,
    hash: string,
    requestedOperationId: string,
  ): Promise<FriendshipSnapshot> {
    const target = (await this.resolveCode(actorId, "", hash)).userId;
    const repeated = this.requests.find((row) => row.operationId === requestedOperationId);
    if (!repeated) {
      this.requests.push({
        id: requestId,
        requesterId: actorId,
        addresseeId: target,
        version: 1,
        status: "pending",
        operationId: requestedOperationId,
      });
    }
    return this.snapshot(actorId);
  }

  async transitionRequest(
    actorId: string,
    _token: string,
    requestedId: string,
    transition: FriendRequestTransition,
    requestedOperationId: string,
    expectedVersion: number,
  ): Promise<FriendshipSnapshot> {
    const row = this.requests.find((item) => item.id === requestedId);
    if (!row || row.status !== "pending" || row.version !== expectedVersion) {
      throw new FriendshipConflictError();
    }
    const allowed = transition === "cancel" ? row.requesterId === actorId : row.addresseeId === actorId;
    if (!allowed) throw new FriendshipConflictError();
    row.status = transition === "accept" ? "accepted" : transition === "reject" ? "rejected" : "cancelled";
    row.version += 1;
    row.operationId = requestedOperationId;
    if (transition === "accept") {
      this.friendships.set([row.requesterId, row.addresseeId].sort().join(":"), {
        version: 1,
        operationId: requestedOperationId,
      });
    }
    return this.snapshot(actorId);
  }

  async removeFriend(
    actorId: string,
    _token: string,
    friendId: string,
    requestedOperationId: string,
    expectedVersion: number,
  ): Promise<FriendshipSnapshot> {
    const pair = [actorId, friendId].sort().join(":");
    const relation = this.friendships.get(pair);
    if (!relation || relation.version !== expectedVersion) throw new FriendshipConflictError();
    this.friendships.delete(pair);
    void requestedOperationId;
    return this.snapshot(actorId);
  }
}

const buildApp = (repository: MemoryFriendshipRepository) => {
  const tokenVerifier: AccessTokenVerifier = {
    verify: async (token) => ({ id: token === "riku-token" ? rikuId : himariId }),
  };
  const dependencies: AppDependencies = {
    tokenVerifier,
    manageProfile: new ManageProfile({
      isAccountActive: async () => true,
      find: async () => null,
      save: async (profile) => profile,
    }),
    manageFriendships: new ManageFriendships(repository, new FixedCodeGenerator()),
    requestDeletion: { execute: async () => { throw new Error("unused"); } },
    deletionStatus: { get: async () => null } satisfies AccountDeletionStatusPort,
  };
  return createApp({}, dependencies);
};

describe("/v1/friendships", () => {
  it("issues a code on the first authenticated snapshot and reuses it", async () => {
    const repository = new MemoryFriendshipRepository();
    const app = buildApp(repository);

    const first = await app.request("/v1/friendships", {
      headers: { authorization: "Bearer himari-token" },
    });
    const second = await app.request("/v1/friendships", {
      headers: { authorization: "Bearer himari-token" },
    });

    expect(first.status).toBe(200);
    expect(await first.json()).toMatchObject({ inviteCode: { value: code } });
    expect(await second.json()).toMatchObject({ inviteCode: { value: code } });
    expect(repository.codes.size).toBe(1);
  });

  it("uses the same public error for unavailable and self-owned codes", async () => {
    const repository = new MemoryFriendshipRepository();
    const app = buildApp(repository);
    await app.request("/v1/friendships", { headers: { authorization: "Bearer himari-token" } });

    for (const unavailable of [code, "HIMA-ZZZZ-ZZZZ-ZZZZ-ZZZZ"]) {
      const response = await app.request("/v1/friendship-invite-code/resolve", {
        method: "POST",
        headers: { authorization: "Bearer himari-token", "content-type": "application/json" },
        body: JSON.stringify({ code: unavailable }),
      });
      expect(response.status).toBe(404);
      expect(await response.json()).toMatchObject({ error: { code: "invite_code_unavailable" } });
    }
  });

  it("creates a pending request once and atomically projects an accepted friendship", async () => {
    const repository = new MemoryFriendshipRepository();
    repository.codes.set(rikuId, {
      value: code,
      hash: `hash:${code}`,
      expiresAt: "2026-09-30T00:00:00.000Z",
    });
    const app = buildApp(repository);

    for (let index = 0; index < 2; index += 1) {
      const sent = await app.request("/v1/friendship-requests", {
        method: "POST",
        headers: { authorization: "Bearer himari-token", "content-type": "application/json" },
        body: JSON.stringify({ code, operationId }),
      });
      expect(sent.status).toBe(200);
    }
    expect(repository.requests).toHaveLength(1);

    const accepted = await app.request(`/v1/friendship-requests/${requestId}/accept`, {
      method: "POST",
      headers: { authorization: "Bearer riku-token", "content-type": "application/json" },
      body: JSON.stringify({ operationId: "00000000-0000-4000-8000-000000000021", expectedVersion: 1 }),
    });

    expect(accepted.status).toBe(200);
    expect(await accepted.json()).toMatchObject({
      incomingRequests: [],
      friends: [{ profile: { userId: himariId, nickname: "ひまり" }, version: 1 }],
    });
  });

  it("returns conflict for a stale request version", async () => {
    const repository = new MemoryFriendshipRepository();
    repository.requests.push({
      id: requestId,
      requesterId: himariId,
      addresseeId: rikuId,
      version: 2,
      status: "pending",
      operationId,
    });
    const response = await buildApp(repository).request(`/v1/friendship-requests/${requestId}/accept`, {
      method: "POST",
      headers: { authorization: "Bearer riku-token", "content-type": "application/json" },
      body: JSON.stringify({ operationId: "00000000-0000-4000-8000-000000000022", expectedVersion: 1 }),
    });

    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ error: { code: "friendship_conflict" } });
  });

  it("rejects incoming, cancels outgoing, and removes an accepted friendship", async () => {
    const repository = new MemoryFriendshipRepository();
    const incomingId = "00000000-0000-4000-8000-000000000031";
    const outgoingId = "00000000-0000-4000-8000-000000000032";
    repository.requests.push({
      id: incomingId,
      requesterId: rikuId,
      addresseeId: himariId,
      version: 1,
      status: "pending",
      operationId: "00000000-0000-4000-8000-000000000041",
    });
    const app = buildApp(repository);
    const mutation = (id: string) => JSON.stringify({ operationId: id, expectedVersion: 1 });

    const rejected = await app.request(`/v1/friendship-requests/${incomingId}/reject`, {
      method: "POST",
      headers: { authorization: "Bearer himari-token", "content-type": "application/json" },
      body: mutation("00000000-0000-4000-8000-000000000051"),
    });
    repository.requests.push({
      id: outgoingId,
      requesterId: himariId,
      addresseeId: rikuId,
      version: 1,
      status: "pending",
      operationId: "00000000-0000-4000-8000-000000000042",
    });
    const cancelled = await app.request(`/v1/friendship-requests/${outgoingId}/cancel`, {
      method: "POST",
      headers: { authorization: "Bearer himari-token", "content-type": "application/json" },
      body: mutation("00000000-0000-4000-8000-000000000052"),
    });

    repository.friendships.set([himariId, rikuId].sort().join(":"), {
      version: 1,
      operationId: "00000000-0000-4000-8000-000000000053",
    });
    const removed = await app.request(`/v1/friendships/${rikuId}`, {
      method: "DELETE",
      headers: { authorization: "Bearer himari-token", "content-type": "application/json" },
      body: mutation("00000000-0000-4000-8000-000000000054"),
    });

    expect(rejected.status).toBe(200);
    expect(cancelled.status).toBe(200);
    expect(removed.status).toBe(200);
    expect(await removed.json()).toMatchObject({ friends: [], incomingRequests: [], outgoingRequests: [] });
  });
});
