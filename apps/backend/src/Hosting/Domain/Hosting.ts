export type HostingCategory = "game" | "meal" | "call" | "work" | null;
export type HostingVisibility = "privateUntilAccepted" | "shareOnHosting";
export type HostingMode = "online" | "offline";
export type HostingArea = "shinjuku" | "shibuya" | "discussLater";
export interface HostingInterval { readonly start: string; readonly end: string }
export interface CreateHostingInput extends HostingInterval {
  readonly mode: HostingMode;
  readonly area: HostingArea | null;
  readonly category: HostingCategory;
  readonly availabilityMetadata: { readonly category: HostingCategory; readonly visibility: HostingVisibility };
  readonly targets: readonly { readonly type: "friend"; readonly id: string }[];
  readonly operationId: string;
}
export interface HostingMutationInput { readonly operationId: string; readonly expectedVersion: number }
export interface HostingResponseInput extends HostingMutationInput {
  readonly status: "accepted" | "declined";
  readonly intervals: readonly HostingInterval[];
}
export interface AcceptedParticipant {
  readonly userId: string;
  readonly nickname: string;
  readonly presetIconKey: string;
  readonly intervals: readonly HostingInterval[];
}
export interface HostingProjection extends HostingInterval {
  readonly id: string;
  readonly host?: { readonly userId: string; readonly nickname: string; readonly presetIconKey: string };
  readonly mode: HostingMode;
  readonly area: HostingArea | null;
  readonly category: HostingCategory;
  readonly status: "open" | "cancelled" | "expired";
  readonly version: number;
  readonly acceptedParticipants?: readonly AcceptedParticipant[];
  readonly myInvitation?: {
    readonly status: "pending" | "accepted" | "declined";
    readonly version: number;
    readonly intervals: readonly HostingInterval[] | null;
  };
}
export class HostingConflictError extends Error { constructor() { super("hosting_conflict"); this.name = "HostingConflictError"; } }
export class HostingUnavailableError extends Error { constructor() { super("hosting_unavailable"); this.name = "HostingUnavailableError"; } }
export class HostingInvalidError extends Error { constructor() { super("hosting_invalid"); this.name = "HostingInvalidError"; } }
export const isUuid = (value: unknown): value is string => typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
