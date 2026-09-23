import type {
  FriendProfile,
  FriendRequestTransition,
  FriendshipSnapshot,
} from "../../Domain/Model/Friendship";

export interface NewInviteCode {
  readonly value: string;
  readonly hash: string;
  readonly expiresAt: string;
}

export interface FriendshipRepository {
  snapshot(actorId: string, accessToken: string): Promise<FriendshipSnapshot>;
  ensureCode(
    actorId: string,
    accessToken: string,
    code: NewInviteCode,
  ): Promise<FriendshipSnapshot>;
  rotateCode(
    actorId: string,
    accessToken: string,
    code: NewInviteCode,
  ): Promise<FriendshipSnapshot>;
  resolveCode(
    actorId: string,
    accessToken: string,
    codeHash: string,
  ): Promise<FriendProfile>;
  sendRequest(
    actorId: string,
    accessToken: string,
    codeHash: string,
    operationId: string,
  ): Promise<FriendshipSnapshot>;
  transitionRequest(
    actorId: string,
    accessToken: string,
    requestId: string,
    transition: FriendRequestTransition,
    operationId: string,
    expectedVersion: number,
  ): Promise<FriendshipSnapshot>;
  removeFriend(
    actorId: string,
    accessToken: string,
    friendId: string,
    operationId: string,
    expectedVersion: number,
  ): Promise<FriendshipSnapshot>;
}
