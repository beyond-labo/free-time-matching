export interface FriendProfile {
  readonly userId: string;
  readonly nickname: string;
  readonly presetIconKey: string;
}

export interface InviteCode {
  readonly value: string;
  readonly expiresAt: string;
}

export interface FriendRequest {
  readonly id: string;
  readonly profile: FriendProfile;
  readonly version: number;
  readonly createdAt: string;
}

export interface Friendship {
  readonly profile: FriendProfile;
  readonly version: number;
  readonly createdAt: string;
}

export interface FriendshipSnapshot {
  readonly inviteCode: InviteCode | null;
  readonly friends: readonly Friendship[];
  readonly incomingRequests: readonly FriendRequest[];
  readonly outgoingRequests: readonly FriendRequest[];
}

export interface FriendshipMutation {
  readonly operationId: string;
  readonly expectedVersion: number;
}

export type FriendRequestTransition = "accept" | "reject" | "cancel";

const inviteCodePattern = /^HIMA(?:-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}){4}$/;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const normalizeInviteCode = (value: string): string =>
  value.trim().toUpperCase();

export const isInviteCode = (value: string): boolean =>
  inviteCodePattern.test(normalizeInviteCode(value));

export const isUUID = (value: string): boolean => uuidPattern.test(value);

export const isVersion = (value: number): boolean =>
  Number.isSafeInteger(value) && value >= 1;

export class InviteCodeUnavailableError extends Error {
  constructor() {
    super("Invite code is unavailable.");
    this.name = "InviteCodeUnavailableError";
  }
}

export class FriendshipUnavailableError extends Error {
  constructor() {
    super("Friendship resource is unavailable.");
    this.name = "FriendshipUnavailableError";
  }
}

export class FriendshipConflictError extends Error {
  constructor() {
    super("Friendship state has changed.");
    this.name = "FriendshipConflictError";
  }
}
