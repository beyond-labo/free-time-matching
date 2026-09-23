import type { FriendshipRepository, NewInviteCode } from "../../Application/Port/FriendshipRepository";
import {
  FriendshipConflictError,
  FriendshipUnavailableError,
  InviteCodeUnavailableError,
  type FriendProfile,
  type FriendRequestTransition,
  type FriendshipSnapshot,
} from "../../Domain/Model/Friendship";
import {
  SupabaseRequestError,
  supabaseFetch,
  type SupabaseRestConfiguration,
} from "../../../Shared/Infrastructure/SupabaseRestClient";
import { AccountDeletionInProgressError } from "../../../User/Application/Port/ProfileRepository";

interface ProfilePayload {
  user_id: string;
  nickname: string;
  preset_icon_key: string;
}

interface InviteCodePayload {
  value: string;
  expires_at: string;
}

interface RequestPayload {
  id: string;
  profile: ProfilePayload;
  version: number;
  created_at: string;
}

interface FriendshipPayload {
  profile: ProfilePayload;
  version: number;
  created_at: string;
}

interface SnapshotPayload {
  invite_code: InviteCodePayload | null;
  friends: FriendshipPayload[];
  incoming_requests: RequestPayload[];
  outgoing_requests: RequestPayload[];
}

const profile = (payload: ProfilePayload): FriendProfile => ({
  userId: payload.user_id,
  nickname: payload.nickname,
  presetIconKey: payload.preset_icon_key,
});

const snapshot = (payload: SnapshotPayload): FriendshipSnapshot => ({
  inviteCode: payload.invite_code
    ? { value: payload.invite_code.value, expiresAt: payload.invite_code.expires_at }
    : null,
  friends: payload.friends.map((item) => ({
    profile: profile(item.profile),
    version: item.version,
    createdAt: item.created_at,
  })),
  incomingRequests: payload.incoming_requests.map((item) => ({
    id: item.id,
    profile: profile(item.profile),
    version: item.version,
    createdAt: item.created_at,
  })),
  outgoingRequests: payload.outgoing_requests.map((item) => ({
    id: item.id,
    profile: profile(item.profile),
    version: item.version,
    createdAt: item.created_at,
  })),
});

export class SupabaseFriendshipRepository implements FriendshipRepository {
  constructor(private readonly configuration: SupabaseRestConfiguration) {}

  async snapshot(_actorId: string, accessToken: string): Promise<FriendshipSnapshot> {
    return snapshot(await this.rpc<SnapshotPayload>("friendship_snapshot", {}, accessToken));
  }

  async rotateCode(
    _actorId: string,
    accessToken: string,
    code: NewInviteCode,
  ): Promise<FriendshipSnapshot> {
    return snapshot(await this.rpc<SnapshotPayload>("rotate_friend_invite_code", {
      p_code: code.value,
      p_code_hash: code.hash,
      p_expires_at: code.expiresAt,
    }, accessToken));
  }

  async ensureCode(
    _actorId: string,
    accessToken: string,
    code: NewInviteCode,
  ): Promise<FriendshipSnapshot> {
    return snapshot(await this.rpc<SnapshotPayload>("ensure_friend_invite_code", {
      p_code: code.value,
      p_code_hash: code.hash,
      p_expires_at: code.expiresAt,
    }, accessToken));
  }

  async resolveCode(
    _actorId: string,
    accessToken: string,
    codeHash: string,
  ): Promise<FriendProfile> {
    return profile(await this.rpc<ProfilePayload>("resolve_friend_invite_code", {
      p_code_hash: codeHash,
    }, accessToken));
  }

  async sendRequest(
    _actorId: string,
    accessToken: string,
    codeHash: string,
    operationId: string,
  ): Promise<FriendshipSnapshot> {
    return snapshot(await this.rpc<SnapshotPayload>("send_friend_request", {
      p_code_hash: codeHash,
      p_operation_id: operationId,
    }, accessToken));
  }

  async transitionRequest(
    _actorId: string,
    accessToken: string,
    requestId: string,
    transition: FriendRequestTransition,
    operationId: string,
    expectedVersion: number,
  ): Promise<FriendshipSnapshot> {
    return snapshot(await this.rpc<SnapshotPayload>("transition_friend_request", {
      p_request_id: requestId,
      p_transition: transition,
      p_operation_id: operationId,
      p_expected_version: expectedVersion,
    }, accessToken));
  }

  async removeFriend(
    _actorId: string,
    accessToken: string,
    friendId: string,
    operationId: string,
    expectedVersion: number,
  ): Promise<FriendshipSnapshot> {
    return snapshot(await this.rpc<SnapshotPayload>("remove_friendship", {
      p_friend_id: friendId,
      p_operation_id: operationId,
      p_expected_version: expectedVersion,
    }, accessToken));
  }

  private async rpc<Result>(
    name: string,
    body: Readonly<Record<string, unknown>>,
    accessToken: string,
  ): Promise<Result> {
    try {
      const response = await supabaseFetch(
        this.configuration,
        `/rest/v1/rpc/${name}`,
        { method: "POST", body: JSON.stringify(body) },
        accessToken,
      );
      return await response.json() as Result;
    } catch (error) {
      if (error instanceof SupabaseRequestError) {
        const message = parseMessage(error.responseBody);
        if (message === "invite_code_unavailable") throw new InviteCodeUnavailableError();
        if (message === "friendship_conflict") throw new FriendshipConflictError();
        if (message === "friendship_unavailable") throw new FriendshipUnavailableError();
        if (message === "account_deletion_in_progress") {
          throw new AccountDeletionInProgressError();
        }
      }
      throw error;
    }
  }
}

const parseMessage = (body: string): string | undefined => {
  try {
    const payload = JSON.parse(body) as { message?: unknown };
    return typeof payload.message === "string" ? payload.message : undefined;
  } catch {
    return undefined;
  }
};
