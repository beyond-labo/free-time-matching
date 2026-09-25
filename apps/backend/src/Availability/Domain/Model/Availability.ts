export const availabilityCategories = ["game", "meal", "call", "work"] as const;
export type AvailabilityCategory = (typeof availabilityCategories)[number];

export const availabilityVisibilities = ["privateUntilAccepted", "shareOnHosting"] as const;
export type AvailabilityVisibility = (typeof availabilityVisibilities)[number];

export interface AvailabilitySlot {
  readonly id: string;
  readonly start: string;
  readonly end: string;
  readonly category: AvailabilityCategory | null;
  readonly visibility: AvailabilityVisibility;
}

export interface AvailabilityInput {
  readonly start: string;
  readonly end: string;
  readonly category: AvailabilityCategory | null;
  readonly visibility: AvailabilityVisibility;
}

export class AvailabilityConflictError extends Error {
  constructor() {
    super("Availability overlaps another slot.");
    this.name = "AvailabilityConflictError";
  }
}

export class AvailabilityUnavailableError extends Error {
  constructor() {
    super("Availability is unavailable.");
    this.name = "AvailabilityUnavailableError";
  }
}

export const isAvailabilityCategory = (value: unknown): value is AvailabilityCategory =>
  typeof value === "string" && (availabilityCategories as readonly string[]).includes(value);

export const isAvailabilityVisibility = (value: unknown): value is AvailabilityVisibility =>
  value === "privateUntilAccepted" || value === "shareOnHosting";

export const isUuid = (value: unknown): value is string =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
