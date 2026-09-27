import type { AvailabilityInput, AvailabilityIntervalOperation, AvailabilitySlot, AvailabilitySubtractOperation } from "../../Domain/Model/Availability";

export interface AvailabilityRepository {
  list(actorId: string, accessToken: string): Promise<AvailabilitySlot[]>;
  upsert(actorId: string, accessToken: string, id: string, input: AvailabilityInput): Promise<AvailabilitySlot>;
  remove(actorId: string, accessToken: string, id: string): Promise<void>;
  union(actorId: string, accessToken: string, input: AvailabilityIntervalOperation): Promise<AvailabilitySlot[]>;
  subtract(actorId: string, accessToken: string, input: AvailabilitySubtractOperation): Promise<AvailabilitySlot[]>;
}
