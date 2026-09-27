import type { HostingRepository } from "../../Application/Port/HostingRepository";
import {
  HostingConflictError, HostingInvalidError, HostingUnavailableError,
  type CreateHostingInput, type HostingMutationInput, type HostingProjection, type HostingResponseInput,
} from "../../Domain/Hosting";
import {
  SupabaseRequestError, supabaseFetch, type SupabaseRestConfiguration,
} from "../../../Shared/Infrastructure/SupabaseRestClient";
import { AccountDeletionInProgressError } from "../../../User/Application/Port/ProfileRepository";

export class SupabaseHostingRepository implements HostingRepository {
  constructor(private readonly configuration: SupabaseRestConfiguration) {}

  async create(_actorId: string, accessToken: string, input: CreateHostingInput): Promise<HostingProjection> {
    const value = await this.rpc("hosting_create", {
      p_start_at: input.start, p_end_at: input.end, p_mode: input.mode,
      p_area: input.area, p_category: input.category, p_targets: input.targets,
      p_availability_category: input.availabilityMetadata.category,
      p_availability_visibility: input.availabilityMetadata.visibility,
      p_operation_id: input.operationId,
    }, accessToken);
    return projectHosting(value);
  }

  async list(_actorId: string, accessToken: string): Promise<HostingProjection[]> {
    const value = await this.rpc("hosting_snapshot", {}, accessToken);
    if (!Array.isArray(value)) throw new HostingUnavailableError();
    return value.map(projectHosting);
  }

  async get(_actorId: string, accessToken: string, hostingId: string): Promise<HostingProjection | null> {
    const value = await this.rpc("hosting_get", { p_hosting_id: hostingId }, accessToken);
    return value === null ? null : projectHosting(value);
  }

  async respond(_actorId: string, accessToken: string, hostingId: string, input: HostingResponseInput): Promise<HostingProjection> {
    const value = await this.rpc("hosting_respond", {
      p_hosting_id: hostingId, p_status: input.status, p_intervals: input.intervals,
      p_operation_id: input.operationId, p_expected_version: input.expectedVersion,
    }, accessToken);
    return projectHosting(value);
  }

  async cancel(_actorId: string, accessToken: string, hostingId: string, input: HostingMutationInput): Promise<HostingProjection> {
    const value = await this.rpc("hosting_cancel", {
      p_hosting_id: hostingId, p_operation_id: input.operationId, p_expected_version: input.expectedVersion,
    }, accessToken);
    return projectHosting(value);
  }

  private async rpc(name: string, body: Record<string, unknown>, accessToken: string): Promise<unknown> {
    try {
      const response = await supabaseFetch(this.configuration, `/rest/v1/rpc/${name}`,
        { method: "POST", body: JSON.stringify(body) }, accessToken);
      return await response.json() as unknown;
    } catch (error) {
      if (error instanceof SupabaseRequestError) {
        const { message, code } = parseError(error.responseBody);
        if (message === "hosting_conflict" || message === "availability_operation_conflict") throw new HostingConflictError();
        if (code === "23514") throw new HostingInvalidError();
        if (message === "hosting_unavailable") throw new HostingUnavailableError();
        if (message === "hosting_invalid" || message === "availability_invalid") throw new HostingInvalidError();
        if (message === "account_deletion_in_progress") throw new AccountDeletionInProgressError();
      }
      throw error;
    }
  }
}

const parseError = (body: string): { message?: string; code?: string } => {
  try {
    const value = JSON.parse(body) as { message?: unknown; code?: unknown };
    return {
      ...(typeof value.message === "string" ? { message: value.message } : {}),
      ...(typeof value.code === "string" ? { code: value.code } : {}),
    };
  } catch { return {}; }
};
const object = (value: unknown): Record<string, unknown> => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new HostingUnavailableError();
  return value as Record<string, unknown>;
};
const string = (value: unknown): string => {
  if (typeof value !== "string") throw new HostingUnavailableError();
  return value;
};
const interval = (value: unknown): { start: string; end: string } => {
  const row = object(value);
  return { start: string(row.start), end: string(row.end) };
};
const intervals = (value: unknown): { start: string; end: string }[] => {
  if (!Array.isArray(value)) throw new HostingUnavailableError();
  return value.map(interval);
};
const profile = (value: unknown) => {
  const row = object(value);
  return { userId: string(row.userId), nickname: string(row.nickname), presetIconKey: string(row.presetIconKey) };
};
const projectHosting = (value: unknown): HostingProjection => {
  const row = object(value);
  const id = string(row.id);
  const start = string(row.start);
  const end = string(row.end);
  const mode = string(row.mode);
  const area = row.area === null ? null : string(row.area);
  const category = row.category === null ? null : string(row.category);
  const status = string(row.status);
  const version = row.version;
  if (!["online", "offline"].includes(mode) || (area !== null && !["shinjuku", "shibuya", "discussLater"].includes(area)) ||
      (category !== null && !["game", "meal", "call", "work"].includes(category)) ||
      !["open", "cancelled", "expired"].includes(status) || typeof version !== "number" || !Number.isSafeInteger(version)) {
    throw new HostingUnavailableError();
  }
  const common = { id, start, end, mode: mode as HostingProjection["mode"], area: area as HostingProjection["area"],
    category: category as HostingProjection["category"], status: status as HostingProjection["status"], version };
  if (row.myInvitation !== undefined && row.myInvitation !== null) {
    const own = object(row.myInvitation);
    const ownStatus = string(own.status);
    if (!["pending", "accepted", "declined"].includes(ownStatus) || typeof own.version !== "number" || !Number.isSafeInteger(own.version)) throw new HostingUnavailableError();
    return {
      ...common,
      ...(row.host === undefined ? {} : { host: profile(row.host) }),
      myInvitation: { status: ownStatus as "pending" | "accepted" | "declined", version: own.version,
        intervals: own.intervals === null ? null : intervals(own.intervals) },
    };
  }
  if (!Array.isArray(row.acceptedParticipants)) throw new HostingUnavailableError();
  return { ...common, acceptedParticipants: row.acceptedParticipants.map((item) => {
    const participant = object(item);
    return { ...profile(participant), intervals: intervals(participant.intervals) };
  }) };
};
