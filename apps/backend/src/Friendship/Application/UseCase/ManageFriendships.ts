import type {
  FriendProfile,
  FriendRequestTransition,
  FriendshipSnapshot,
} from "../../Domain/Model/Friendship";
import { normalizeInviteCode } from "../../Domain/Model/Friendship";
import type {
  FriendshipRepository,
  NewInviteCode,
} from "../Port/FriendshipRepository";

const codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const inviteCodeLifetimeMs = 7 * 24 * 60 * 60 * 1_000;

export interface FriendshipCodeGenerator {
  generate(now?: Date): Promise<NewInviteCode>;
  hash(value: string): Promise<string>;
}

export class SecureFriendshipCodeGenerator implements FriendshipCodeGenerator {
  async generate(now = new Date()): Promise<NewInviteCode> {
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    const characters = Array.from(
      bytes,
      (byte) => codeAlphabet[byte & 31] ?? codeAlphabet[0],
    ).join("");
    const groups = characters.match(/.{4}/g);
    if (!groups) throw new Error("Failed to generate invite code.");
    const value = `HIMA-${groups.join("-")}`;
    return {
      value,
      hash: await this.hash(value),
      expiresAt: new Date(now.getTime() + inviteCodeLifetimeMs).toISOString(),
    };
  }

  async hash(value: string): Promise<string> {
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(normalizeInviteCode(value)),
    );
    return Array.from(new Uint8Array(digest), (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");
  }
}

export class ManageFriendships {
  constructor(
    private readonly repository: FriendshipRepository,
    private readonly codes: FriendshipCodeGenerator = new SecureFriendshipCodeGenerator(),
  ) {}

  async snapshot(actorId: string, accessToken: string): Promise<FriendshipSnapshot> {
    const current = await this.repository.snapshot(actorId, accessToken);
    if (current.inviteCode) return current;
    return this.repository.ensureCode(
      actorId,
      accessToken,
      await this.codes.generate(),
    );
  }

  async rotateCode(actorId: string, accessToken: string): Promise<FriendshipSnapshot> {
    return this.repository.rotateCode(
      actorId,
      accessToken,
      await this.codes.generate(),
    );
  }

  async resolveCode(
    actorId: string,
    accessToken: string,
    code: string,
  ): Promise<FriendProfile> {
    return this.repository.resolveCode(
      actorId,
      accessToken,
      await this.codes.hash(code),
    );
  }

  async sendRequest(
    actorId: string,
    accessToken: string,
    code: string,
    operationId: string,
  ): Promise<FriendshipSnapshot> {
    return this.repository.sendRequest(
      actorId,
      accessToken,
      await this.codes.hash(code),
      operationId,
    );
  }

  async transitionRequest(
    actorId: string,
    accessToken: string,
    requestId: string,
    transition: FriendRequestTransition,
    operationId: string,
    expectedVersion: number,
  ): Promise<FriendshipSnapshot> {
    return this.repository.transitionRequest(
      actorId,
      accessToken,
      requestId,
      transition,
      operationId,
      expectedVersion,
    );
  }

  async removeFriend(
    actorId: string,
    accessToken: string,
    friendId: string,
    operationId: string,
    expectedVersion: number,
  ): Promise<FriendshipSnapshot> {
    return this.repository.removeFriend(
      actorId,
      accessToken,
      friendId,
      operationId,
      expectedVersion,
    );
  }
}
