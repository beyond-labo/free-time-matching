export type ProposalStatus = "pending" | "confirmed" | "declined" | "expired" | "cancelled";
export type ParticipationResponse = "pending" | "accepted" | "declined";
export type ReportReason = "spam" | "harassment" | "other";
export interface SchedulingOperation { readonly operationId: string }
export interface SchedulingMutation extends SchedulingOperation { readonly expectedVersion: number }
export interface SchedulingSettingsInput extends SchedulingOperation { readonly enabled: boolean }
export interface SchedulingResponseInput extends SchedulingMutation {
  readonly response: "accepted" | "declined";
  readonly shareAcceptance: boolean;
}
export interface SchedulingFeedback {
  readonly played: boolean;
  readonly bothersome: boolean;
  readonly privacyConcern: boolean;
}
export interface SchedulingFeedbackInput extends SchedulingFeedback, SchedulingOperation {}
export interface SchedulingReportInput extends SchedulingOperation { readonly reason: ReportReason }
export interface SchedulingDeviceInput {
  readonly token: string;
  readonly environment: "sandbox" | "production";
  readonly enabled: boolean;
}
export interface SchedulingProposal {
  readonly id: string;
  readonly start: string;
  readonly end: string;
  readonly status: ProposalStatus;
  readonly myResponse: ParticipationResponse;
  readonly version: number;
  readonly shareAcceptance: boolean;
  readonly peer?: { readonly userId: string; readonly nickname: string; readonly presetIconKey: string };
  readonly peerResponse?: "accepted";
  readonly feedback?: SchedulingFeedback;
}
export interface SchedulingSnapshot {
  readonly enabled: boolean;
  readonly permissions: readonly { readonly friendId: string; readonly enabled: boolean }[];
  readonly proposals: readonly SchedulingProposal[];
  readonly notifications: readonly {
    readonly id: string;
    readonly proposalId: string;
    readonly kind: "proposal" | "confirmed" | "cancelled";
    readonly createdAt: string;
  }[];
}
export class SchedulingConflictError extends Error {
  constructor() { super("automatic_scheduling_conflict"); this.name = "SchedulingConflictError"; }
}
export class SchedulingUnavailableError extends Error {
  constructor() { super("automatic_scheduling_unavailable"); this.name = "SchedulingUnavailableError"; }
}
export class SchedulingInvalidError extends Error {
  constructor() { super("automatic_scheduling_invalid"); this.name = "SchedulingInvalidError"; }
}
export const isSchedulingUuid = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
