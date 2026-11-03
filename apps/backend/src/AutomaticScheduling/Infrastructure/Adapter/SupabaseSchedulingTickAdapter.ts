import { supabaseFetch } from "../../../Shared/Infrastructure/SupabaseRestClient";

export interface SchedulingTickBindings {
  readonly SUPABASE_URL?: string;
  readonly SUPABASE_SECRET_KEY?: string;
}

/** The privileged job is separate from repositories that always carry a user's JWT. */
export const runAutomaticSchedulingTick = async (bindings: SchedulingTickBindings): Promise<void> => {
  if (!bindings.SUPABASE_URL || !bindings.SUPABASE_SECRET_KEY) throw new Error("Scheduling job configuration is incomplete.");
  const response = await supabaseFetch({ url: bindings.SUPABASE_URL, apiKey: bindings.SUPABASE_SECRET_KEY },
    "/rest/v1/rpc/automatic_scheduling_tick", { method: "POST", body: "{}" });
  const count: unknown = await response.json();
  if (typeof count !== "number" || !Number.isSafeInteger(count) || count < 0) throw new Error("Invalid scheduling job result.");
};
