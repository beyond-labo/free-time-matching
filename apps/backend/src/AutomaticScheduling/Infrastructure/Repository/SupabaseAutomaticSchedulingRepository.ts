import type { AutomaticSchedulingRepository } from "../../Application/Port/AutomaticSchedulingRepository";
import {
  SchedulingConflictError, SchedulingInvalidError, SchedulingUnavailableError, isSchedulingUuid,
  type SchedulingSnapshot, type SchedulingProposal, type SchedulingSettingsInput,
  type SchedulingResponseInput, type SchedulingMutation, type SchedulingFeedbackInput,
  type SchedulingOperation, type SchedulingReportInput, type SchedulingDeviceInput,
} from "../../Domain/Model/AutomaticScheduling";
import { SupabaseRequestError, supabaseFetch, type SupabaseRestConfiguration } from "../../../Shared/Infrastructure/SupabaseRestClient";
import { AccountDeletionInProgressError } from "../../../User/Application/Port/ProfileRepository";

export class SupabaseAutomaticSchedulingRepository implements AutomaticSchedulingRepository {
  constructor(private readonly configuration: SupabaseRestConfiguration) {}

  snapshot(_actorId: string, token: string): Promise<SchedulingSnapshot> {
    return this.rpc("snapshot", {}, token);
  }
  settings(_actorId: string, token: string, input: SchedulingSettingsInput): Promise<SchedulingSnapshot> {
    return this.rpc("settings", { p_enabled: input.enabled, p_operation_id: input.operationId }, token);
  }
  permission(_actorId: string, token: string, friendId: string, input: SchedulingSettingsInput): Promise<SchedulingSnapshot> {
    return this.rpc("permission", { p_friend_id: friendId, p_enabled: input.enabled, p_operation_id: input.operationId }, token);
  }
  respond(_actorId: string, token: string, proposalId: string, input: SchedulingResponseInput): Promise<SchedulingSnapshot> {
    return this.rpc("respond", { p_proposal_id: proposalId, p_response: input.response,
      p_share_acceptance: input.shareAcceptance, p_operation_id: input.operationId, p_expected_version: input.expectedVersion }, token);
  }
  cancel(_actorId: string, token: string, proposalId: string, input: SchedulingMutation): Promise<SchedulingSnapshot> {
    return this.rpc("cancel", { p_proposal_id: proposalId, p_operation_id: input.operationId, p_expected_version: input.expectedVersion }, token);
  }
  feedback(_actorId: string, token: string, proposalId: string, input: SchedulingFeedbackInput): Promise<SchedulingSnapshot> {
    return this.rpc("feedback", { p_proposal_id: proposalId, p_played: input.played,
      p_bothersome: input.bothersome, p_privacy_concern: input.privacyConcern, p_operation_id: input.operationId }, token);
  }
  block(_actorId: string, token: string, friendId: string, input: SchedulingOperation): Promise<SchedulingSnapshot> {
    return this.rpc("block", { p_friend_id: friendId, p_operation_id: input.operationId }, token);
  }
  blockProposal(_actorId: string, token: string, proposalId: string, input: SchedulingOperation): Promise<SchedulingSnapshot> {
    return this.rpc("block_proposal", { p_proposal_id: proposalId, p_operation_id: input.operationId }, token);
  }
  report(_actorId: string, token: string, proposalId: string, input: SchedulingReportInput): Promise<SchedulingSnapshot> {
    return this.rpc("report", { p_proposal_id: proposalId, p_reason: input.reason, p_operation_id: input.operationId }, token);
  }
  reportFriend(_actorId: string, token: string, friendId: string, input: SchedulingReportInput): Promise<SchedulingSnapshot> {
    return this.rpc("report_friend", { p_friend_id: friendId, p_reason: input.reason, p_operation_id: input.operationId }, token);
  }
  device(_actorId: string, token: string, input: SchedulingDeviceInput): Promise<SchedulingSnapshot> {
    return this.rpc("device", { p_token: input.token, p_environment: input.environment, p_enabled: input.enabled }, token);
  }

  private async rpc(name: string, body: Record<string, unknown>, token: string): Promise<SchedulingSnapshot> {
    try {
      const response = await supabaseFetch(this.configuration, `/rest/v1/rpc/automatic_scheduling_${name}`,
        { method: "POST", body: JSON.stringify(body) }, token);
      return projectSchedulingSnapshot(await response.json() as unknown);
    } catch (error) {
      if (error instanceof SupabaseRequestError) {
        const { code, message } = databaseError(error.responseBody);
        if (message === "account_deletion_in_progress") throw new AccountDeletionInProgressError();
        if (message === "scheduling_conflict" || message === "automatic_scheduling_conflict" || code === "40001" || code === "23505") throw new SchedulingConflictError();
        if (message === "scheduling_invalid" || message === "automatic_scheduling_invalid" || code === "23514") throw new SchedulingInvalidError();
        if (message === "scheduling_unavailable" || message === "automatic_scheduling_unavailable" || code === "42501" || code === "P0002") throw new SchedulingUnavailableError();
      }
      throw error;
    }
  }
}

const databaseError = (body: string): { code?: string; message?: string } => {
  try {
    const value = JSON.parse(body) as { code?: unknown; message?: unknown };
    return { code: typeof value.code === "string" ? value.code : undefined,
      message: typeof value.message === "string" ? value.message : undefined };
  } catch { return {}; }
};
const object = (value: unknown): Record<string, unknown> => {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid scheduling projection.");
  return value as Record<string, unknown>;
};
const string = (value: unknown): string => {
  if (typeof value !== "string") throw new Error("Invalid scheduling projection.");
  return value;
};
const uuid = (value: unknown): string => {
  if (!isSchedulingUuid(value)) throw new Error("Invalid scheduling projection.");
  return value;
};
const boolean = (value: unknown): boolean => {
  if (typeof value !== "boolean") throw new Error("Invalid scheduling projection.");
  return value;
};
const array = (value: unknown): unknown[] => {
  if (!Array.isArray(value)) throw new Error("Invalid scheduling projection.");
  return value;
};
const instant = (value: unknown): string => {
  const raw = string(value);
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$/.test(raw) || !Number.isFinite(Date.parse(raw))) {
    throw new Error("Invalid scheduling projection.");
  }
  return new Date(raw).toISOString();
};
const feedback = (value: unknown) => {
  const row = object(value);
  return { played: boolean(row.played), bothersome: boolean(row.bothersome), privacyConcern: boolean(row.privacyConcern) };
};
const proposal = (value: unknown): SchedulingProposal => {
  const row = object(value);
  const status = string(row.status);
  const myResponse = string(row.myResponse);
  const start = instant(row.start);
  const end = instant(row.end);
  if (!["pending", "confirmed", "declined", "expired", "cancelled"].includes(status) ||
      !["pending", "accepted", "declined"].includes(myResponse) ||
      typeof row.version !== "number" || !Number.isSafeInteger(row.version) || row.version < 1 ||
      Date.parse(start) >= Date.parse(end) || Date.parse(end) - Date.parse(start) > 86400000 ||
      Date.parse(start) % 900000 !== 0 || Date.parse(end) % 900000 !== 0) {
    throw new Error("Invalid scheduling projection.");
  }
  const result: SchedulingProposal = { id: uuid(row.id), start, end,
    status: status as SchedulingProposal["status"], myResponse: myResponse as SchedulingProposal["myResponse"],
    version: row.version, shareAcceptance: boolean(row.shareAcceptance),
    ...(row.feedback === undefined || row.feedback === null ? {} : { feedback: feedback(row.feedback) }) };
  // Never forward RPC objects wholesale. In particular, leaked raw profile/answer
  // fields in an anonymous proposal must not become part of the public HTTP DTO.
  if (status === "pending" && row.peerResponse === "accepted" && (row.peer === undefined || row.peer === null)) {
    throw new Error("Invalid scheduling projection.");
  }
  if ((status === "confirmed" || (status === "pending" && row.peerResponse === "accepted")) &&
      row.peer !== undefined && row.peer !== null) {
    const peer = object(row.peer);
    return { ...result, peer: { userId: uuid(peer.userId), nickname: string(peer.nickname), presetIconKey: string(peer.presetIconKey) },
      ...(row.peerResponse === "accepted" ? { peerResponse: "accepted" as const } : {}) };
  }
  return result;
};

export const projectSchedulingSnapshot = (value: unknown): SchedulingSnapshot => {
  const row = object(value);
  return { enabled: boolean(row.enabled),
    permissions: array(row.permissions).map((item) => {
      const entry = object(item);
      return { friendId: uuid(entry.friendId), enabled: boolean(entry.enabled) };
    }),
    proposals: array(row.proposals).map(proposal),
    notifications: array(row.notifications).map((item) => {
      const entry = object(item);
      const kind = string(entry.kind);
      if (!["proposal", "confirmed", "cancelled"].includes(kind)) throw new Error("Invalid scheduling projection.");
      return { id: uuid(entry.id), proposalId: uuid(entry.proposalId),
        kind: kind as SchedulingSnapshot["notifications"][number]["kind"], createdAt: instant(entry.createdAt) };
    }),
  };
};
