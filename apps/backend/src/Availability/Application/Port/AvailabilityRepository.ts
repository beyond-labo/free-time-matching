import type { AvailabilityInput, AvailabilitySlot } from "../../Domain/Model/Availability";

export interface AvailabilityRepository {
  list(actorId: string, accessToken: string): Promise<AvailabilitySlot[]>;
  upsert(actorId: string, accessToken: string, id: string, input: AvailabilityInput): Promise<AvailabilitySlot>;
  remove(actorId: string, accessToken: string, id: string): Promise<void>;
}
