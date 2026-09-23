import { describe, expect, it } from "vitest";
import type { AccessTokenVerifier } from "../src/Auth/Application/Port/AccessTokenVerifier";
import type {
  AccountDeletionAdminPort,
  AccountDeletionStatusPort,
  AppleAuthorizationGateway,
  AppleAuthorizationResult,
  CurrentIdentityGateway,
} from "../src/AccountDeletion/Application/Port/AccountDeletionPorts";
import { RequestAccountDeletion } from "../src/AccountDeletion/Application/UseCase/RequestAccountDeletion";
import type {
  AccountDeletionRecord,
  AccountDeletionStatus,
} from "../src/AccountDeletion/Domain/Model/AccountDeletion";
import { HmacStatusTokenIssuer } from "../src/AccountDeletion/Infrastructure/Adapter/HmacStatusTokenIssuer";
import { createApp, type AppDependencies } from "../src/Composition/createApp";
import { ManageProfile } from "../src/User/Application/UseCase/ManageProfile";

const userId = "8e26166a-a14a-4933-a953-199798829ab5";

class MemoryDeletionAdmin implements AccountDeletionAdminPort {
  records: AccountDeletionRecord[] = [];
  events: string[] = [];
  failDelete = false;
  conflictRecord: AccountDeletionRecord | null = null;

  async findByIdempotencyKey(user: string, key: string) {
    return this.records.find(
      (record) => record.userId === user && record.idempotencyKey === key,
    ) ?? null;
  }

  async createAccepted(input: {
    userId: string;
    idempotencyKey: string;
    reference: string;
  }) {
    if (this.conflictRecord) return this.conflictRecord;
    this.events.push("accepted");
    const record: AccountDeletionRecord = {
      id: crypto.randomUUID(),
      ...input,
      status: "accepted",
    };
    this.records.push(record);
    return record;
  }

  async setStatus(id: string, status: AccountDeletionStatus, message?: string) {
    this.events.push(status);
    const index = this.records.findIndex((record) => record.id === id);
    this.records[index] = { ...this.records[index], status, ...(message ? { message } : {}) };
    return this.records[index];
  }

  async deleteAuthUser() {
    this.events.push("delete-auth-user");
    if (this.failDelete) throw new Error("delete failed");
  }
}

class FakeAppleGateway implements AppleAuthorizationGateway {
  exchangeCount = 0;
  constructor(
    readonly subject = "apple-subject",
    private readonly events: string[] = [],
  ) {}

  async exchange(): Promise<AppleAuthorizationResult> {
    this.exchangeCount += 1;
    return {
      subject: this.subject,
      revocationToken: "apple-refresh-token",
      tokenTypeHint: "refresh_token",
    };
  }

  async revoke(): Promise<void> {
    this.events.push("revoke-apple");
  }
}

const createDeletionApp = (admin: MemoryDeletionAdmin, apple: FakeAppleGateway) => {
  const tokenVerifier: AccessTokenVerifier = {
    verify: async () => ({ id: userId }),
  };
  const identity: CurrentIdentityGateway = {
    appleSubject: async () => "apple-subject",
  };
  const statusTokens = new HmacStatusTokenIssuer("a".repeat(32));
  const requestDeletion = new RequestAccountDeletion(
    admin,
    apple,
    identity,
    statusTokens,
  );
  const deletionStatus: AccountDeletionStatusPort = {
    get: async (reference, token) => {
      const record = admin.records.find((item) => item.reference === reference);
      if (!record || (await statusTokens.issue(reference)) !== token) return null;
      return {
        reference,
        status: record.status,
        ...(record.message ? { message: record.message } : {}),
      };
    },
  };
  const dependencies: AppDependencies = {
    tokenVerifier,
    manageProfile: new ManageProfile({
      isAccountActive: async () => true,
      find: async () => null,
      save: async (profile) => profile,
    }),
    manageFriendships: {
      snapshot: async () => { throw new Error("unused"); },
      rotateCode: async () => { throw new Error("unused"); },
      resolveCode: async () => { throw new Error("unused"); },
      sendRequest: async () => { throw new Error("unused"); },
      transitionRequest: async () => { throw new Error("unused"); },
      removeFriend: async () => { throw new Error("unused"); },
    },
    requestDeletion,
    deletionStatus,
  };
  return createApp({}, dependencies);
};

const deleteRequest = (app: ReturnType<typeof createApp>, key = "operation-123") =>
  app.request("/v1/account-deletion-requests", {
    method: "POST",
    headers: {
      authorization: "Bearer valid-token",
      "idempotency-key": key,
      "content-type": "application/json",
    },
    body: JSON.stringify({ appleAuthorizationCode: "fresh-code" }),
  });

describe("account deletion API", () => {
  it("revokes Apple before hard-deleting auth and returns a completed receipt", async () => {
    const admin = new MemoryDeletionAdmin();
    const apple = new FakeAppleGateway("apple-subject", admin.events);
    const response = await deleteRequest(createDeletionApp(admin, apple));
    const body = (await response.json()) as Record<string, string>;

    expect(response.status).toBe(200);
    expect(body).toMatchObject({ status: "completed", statusToken: expect.any(String) });
    expect(admin.events).toEqual([
      "accepted",
      "processing",
      "revoke-apple",
      "delete-auth-user",
      "completed",
    ]);
  });

  it("replays the same completed receipt without exchanging the Apple code again", async () => {
    const admin = new MemoryDeletionAdmin();
    const apple = new FakeAppleGateway();
    const app = createDeletionApp(admin, apple);
    const first = (await (await deleteRequest(app)).json()) as Record<string, string>;
    const second = (await (await deleteRequest(app)).json()) as Record<string, string>;

    expect(second).toEqual(first);
    expect(apple.exchangeCount).toBe(1);
  });

  it("preserves an accepted winner when a concurrent idempotency insert loses", async () => {
    const admin = new MemoryDeletionAdmin();
    admin.conflictRecord = {
      id: crypto.randomUUID(),
      userId,
      idempotencyKey: "operation-123",
      reference: "DEL-CONCURRENT",
      status: "accepted",
    };
    const response = await deleteRequest(createDeletionApp(admin, new FakeAppleGateway()));

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      reference: "DEL-CONCURRENT",
      status: "accepted",
      statusToken: expect.any(String),
    });
    expect(admin.events).toEqual([]);
  });

  it("keeps access stopped and returns actionRequired when hard deletion fails", async () => {
    const admin = new MemoryDeletionAdmin();
    admin.failDelete = true;
    const response = await deleteRequest(createDeletionApp(admin, new FakeAppleGateway()));

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      status: "actionRequired",
      statusToken: expect.any(String),
      message: expect.any(String),
    });
    expect(admin.records[0].status).toBe("actionRequired");
  });

  it("rejects an Apple credential belonging to a different identity", async () => {
    const admin = new MemoryDeletionAdmin();
    const response = await deleteRequest(
      createDeletionApp(admin, new FakeAppleGateway("different-apple-subject")),
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({
      error: { code: "apple_reauthentication_failed" },
    });
    expect(admin.records).toEqual([]);
  });

  it("uses the opaque Deletion authorization scheme for status lookup", async () => {
    const admin = new MemoryDeletionAdmin();
    const app = createDeletionApp(admin, new FakeAppleGateway());
    const receipt = (await (await deleteRequest(app)).json()) as Record<string, string>;
    const response = await app.request(
      `/v1/account-deletion-requests/${receipt.reference}`,
      { headers: { authorization: `Deletion ${receipt.statusToken}` } },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      reference: receipt.reference,
      status: "completed",
    });
  });
});
