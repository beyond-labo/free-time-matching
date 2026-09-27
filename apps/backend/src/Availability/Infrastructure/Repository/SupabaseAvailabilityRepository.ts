import {
  AvailabilityConflictError,
  AvailabilityHostingConflictError,
  AvailabilityUnavailableError,
  type AvailabilityInput,
  type AvailabilityIntervalOperation,
  type AvailabilitySlot,
  type AvailabilitySubtractOperation,
} from "../../Domain/Model/Availability";
import {
  SupabaseRequestError,
  supabaseFetch,
  type SupabaseRestConfiguration,
} from "../../../Shared/Infrastructure/SupabaseRestClient";
import type { AvailabilityRepository } from "../../Application/Port/AvailabilityRepository";

interface AvailabilityPayload {
  id: string;
  start_at: string;
  end_at: string;
  category: AvailabilitySlot["category"];
  visibility: AvailabilitySlot["visibility"];
}

const project = (row: AvailabilityPayload): AvailabilitySlot => ({
  id: row.id,
  start: row.start_at,
  end: row.end_at,
  category: row.category,
  visibility: row.visibility,
});

export class SupabaseAvailabilityRepository implements AvailabilityRepository {
  constructor(private readonly configuration: SupabaseRestConfiguration) {}

  async list(_actorId: string, accessToken: string): Promise<AvailabilitySlot[]> {
    const now = new Date();
    const windowEnd = new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000);
    const response = await this.request(
      `/rest/v1/availability_slots?select=id,start_at,end_at,category,visibility&end_at=gt.${encodeURIComponent(now.toISOString())}&start_at=lt.${encodeURIComponent(windowEnd.toISOString())}&order=start_at.asc`,
      { method: "GET" },
      accessToken,
    );
    return (await response.json() as AvailabilityPayload[]).map(project);
  }

  async upsert(
    actorId: string,
    accessToken: string,
    id: string,
    input: AvailabilityInput,
  ): Promise<AvailabilitySlot> {
    try {
      const response = await this.request(
        "/rest/v1/availability_slots",
        {
          method: "POST",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify({
            id,
            owner_user_id: actorId,
            start_at: input.start,
            end_at: input.end,
            category: input.category,
            visibility: input.visibility,
          }),
        },
        accessToken,
      );
      const rows = await response.json() as AvailabilityPayload[];
      const row = rows[0];
      if (!row) throw new AvailabilityUnavailableError();
      return project(row);
    } catch (error) {
      if (!(error instanceof AvailabilityConflictError)) throw error;
      // The normal create path is one Supabase round trip. Only a conflicting
      // replay needs a read to distinguish an identical retry from a new value.
      const existingResponse = await this.request(
        `/rest/v1/availability_slots?id=eq.${encodeURIComponent(id)}&select=id,start_at,end_at,category,visibility`,
        { method: "GET" },
        accessToken,
      );
      const existing = (await existingResponse.json() as AvailabilityPayload[])[0];
      if (!existing) throw error;
      const current = project(existing);
      if (
        new Date(current.start).getTime() !== new Date(input.start).getTime() ||
        new Date(current.end).getTime() !== new Date(input.end).getTime() ||
        current.category !== input.category ||
        current.visibility !== input.visibility
      ) throw error;
      return current;
    }
  }

  async remove(_actorId: string, accessToken: string, id: string): Promise<void> {
    await this.request(
      `/rest/v1/availability_slots?id=eq.${encodeURIComponent(id)}`,
      { method: "DELETE" },
      accessToken,
    );
  }

  async union(_actorId: string, accessToken: string, input: AvailabilityIntervalOperation): Promise<AvailabilitySlot[]> {
    const response = await this.request("/rest/v1/rpc/availability_union_interval", {
      method: "POST",
      body: JSON.stringify({
        p_start_at: input.start, p_end_at: input.end, p_category: input.category,
        p_visibility: input.visibility, p_operation_id: input.operationId,
      }),
    }, accessToken);
    return projectSlots(await response.json());
  }

  async subtract(_actorId: string, accessToken: string, input: AvailabilitySubtractOperation): Promise<AvailabilitySlot[]> {
    const response = await this.request("/rest/v1/rpc/availability_subtract_interval", {
      method: "POST",
      body: JSON.stringify({ p_start_at: input.start, p_end_at: input.end, p_operation_id: input.operationId }),
    }, accessToken);
    return projectSlots(await response.json());
  }

  private async request(path: string, init: RequestInit, accessToken: string): Promise<Response> {
    try {
      return await supabaseFetch(this.configuration, path, init, accessToken);
    } catch (error) {
      if (error instanceof SupabaseRequestError) {
        const code = parseErrorCode(error.responseBody);
        if (code === "availability_hosting_conflict") throw new AvailabilityHostingConflictError();
        if (code === "23P01" || code === "23505" || code === "availability_overlap") throw new AvailabilityConflictError();
        if (code === "availability_invalid" || code === "23514" || code === "22P02") {
          throw new AvailabilityUnavailableError();
        }
      }
      throw error;
    }
  }
}

const parseErrorCode = (body: string): string | undefined => {
  try {
    const value = JSON.parse(body) as { code?: unknown; message?: unknown };
    if (value.message === "availability_hosting_conflict") return "availability_hosting_conflict";
    if (typeof value.code === "string") return value.code;
    if (typeof value.message === "string" && value.message === "availability_overlap") return value.message;
  } catch {
    // Do not expose or log Supabase response bodies.
  }
  return undefined;
};

const projectSlots = (value: unknown): AvailabilitySlot[] => {
  if (!Array.isArray(value)) throw new AvailabilityUnavailableError();
  return value.map((row) => {
    if (typeof row !== "object" || row === null) throw new AvailabilityUnavailableError();
    const record = row as Record<string, unknown>;
    if (typeof record.id !== "string" || typeof record.start_at !== "string" || typeof record.end_at !== "string") throw new AvailabilityUnavailableError();
    return project({
      id: record.id,
      start_at: record.start_at,
      end_at: record.end_at,
      category: record.category as AvailabilitySlot["category"],
      visibility: record.visibility as AvailabilitySlot["visibility"],
    });
  });
};
