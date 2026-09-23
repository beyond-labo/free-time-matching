import { describe, expect, it } from "vitest";
import type { AccessTokenVerifier } from "../src/Auth/Application/Port/AccessTokenVerifier";
import type { AccountDeletionStatusPort } from "../src/AccountDeletion/Application/Port/AccountDeletionPorts";
import type { RequestAccountDeletion } from "../src/AccountDeletion/Application/UseCase/RequestAccountDeletion";
import { createApp, type AppDependencies } from "../src/Composition/createApp";
import { ManageProfile } from "../src/User/Application/UseCase/ManageProfile";
import type { ProfileRepository } from "../src/User/Application/Port/ProfileRepository";
import type { UserProfile } from "../src/User/Domain/Model/UserProfile";

const userId = "8e26166a-a14a-4933-a953-199798829ab5";

class MemoryProfileRepository implements ProfileRepository {
  active = true;
  profile: UserProfile | null = null;

  async isAccountActive(): Promise<boolean> {
    return this.active;
  }

  async find(): Promise<UserProfile | null> {
    return this.profile;
  }

  async save(profile: UserProfile): Promise<UserProfile> {
    this.profile = profile;
    return profile;
  }
}

const buildApp = (repository: MemoryProfileRepository) => {
  const tokenVerifier: AccessTokenVerifier = {
    verify: async (token) => {
      if (token !== "valid-token") throw new Error("unexpected test token");
      return { id: userId };
    },
  };
  const dependencies: AppDependencies = {
    tokenVerifier,
    manageProfile: new ManageProfile(repository),
    manageFriendships: {
      snapshot: async () => { throw new Error("unused"); },
      rotateCode: async () => { throw new Error("unused"); },
      resolveCode: async () => { throw new Error("unused"); },
      sendRequest: async () => { throw new Error("unused"); },
      transitionRequest: async () => { throw new Error("unused"); },
      removeFriend: async () => { throw new Error("unused"); },
    },
    requestDeletion: {
      execute: async () => {
        throw new Error("unused");
      },
    },
    deletionStatus: {
      get: async () => null,
    } satisfies AccountDeletionStatusPort,
  };
  return createApp({}, dependencies);
};

describe("/v1/me", () => {
  it("returns null until the profile is configured", async () => {
    const response = await buildApp(new MemoryProfileRepository()).request("/v1/me", {
      headers: { authorization: "Bearer valid-token" },
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ userId, profile: null });
  });

  it("normalizes and persists an allowed profile", async () => {
    const repository = new MemoryProfileRepository();
    const response = await buildApp(repository).request("/v1/me", {
      method: "PUT",
      headers: {
        authorization: "Bearer valid-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({ nickname: " ひまり ", presetIconKey: "sun.max.fill" }),
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      userId,
      profile: { nickname: "ひまり", presetIconKey: "sun.max.fill" },
    });
  });

  it("counts extended emoji as graphemes and rejects more than twenty", async () => {
    const response = await buildApp(new MemoryProfileRepository()).request("/v1/me", {
      method: "PUT",
      headers: {
        authorization: "Bearer valid-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        nickname: "👨‍👩‍👧‍👦".repeat(21),
        presetIconKey: "leaf.fill",
      }),
    });

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      error: { code: "invalid_profile", fields: { nickname: expect.any(String) } },
    });
  });

  it("accepts twenty joined emoji as twenty graphemes", async () => {
    const nickname = "👨‍👩‍👧‍👦".repeat(20);
    const response = await buildApp(new MemoryProfileRepository()).request("/v1/me", {
      method: "PUT",
      headers: {
        authorization: "Bearer valid-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({ nickname, presetIconKey: "figure.run" }),
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      profile: { nickname, presetIconKey: "figure.run" },
    });
  });

  it("rejects icons outside the server allowlist", async () => {
    const response = await buildApp(new MemoryProfileRepository()).request("/v1/me", {
      method: "PUT",
      headers: {
        authorization: "Bearer valid-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({ nickname: "ひまり", presetIconKey: "person.crop.circle" }),
    });

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      error: { code: "invalid_profile", fields: { presetIconKey: expect.any(String) } },
    });
  });

  it("blocks normal profile access after deletion is accepted", async () => {
    const repository = new MemoryProfileRepository();
    repository.active = false;
    const response = await buildApp(repository).request("/v1/me", {
      headers: { authorization: "Bearer valid-token" },
    });

    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({
      error: { code: "account_deletion_in_progress" },
    });
  });
});
