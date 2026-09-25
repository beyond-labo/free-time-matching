import {
  AvailabilityConflictError,
  AvailabilityUnavailableError,
  type AvailabilityInput,
  type AvailabilitySlot,
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

  private async request(path: string, init: RequestInit, accessToken: string): Promise<Response> {
    try {
      return await supabaseFetch(this.configuration, path, init, accessToken);
    } catch (error) {
      if (error instanceof SupabaseRequestError) {
        const code = parseErrorCode(error.responseBody);
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
    if (typeof value.code === "string") return value.code;
    if (typeof value.message === "string" && value.message === "availability_overlap") return value.message;
  } catch {
    // Do not expose or log Supabase response bodies.
  }
  return undefined;
};
