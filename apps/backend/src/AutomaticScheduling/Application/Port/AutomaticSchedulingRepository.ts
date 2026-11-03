import type {
  SchedulingSnapshot, SchedulingSettingsInput, SchedulingResponseInput,
  SchedulingMutation, SchedulingFeedbackInput, SchedulingOperation,
  SchedulingReportInput, SchedulingDeviceInput,
} from "../../Domain/Model/AutomaticScheduling";

export interface AutomaticSchedulingRepository {
  snapshot(actorId: string, accessToken: string): Promise<SchedulingSnapshot>;
  settings(actorId: string, accessToken: string, input: SchedulingSettingsInput): Promise<SchedulingSnapshot>;
  permission(actorId: string, accessToken: string, friendId: string, input: SchedulingSettingsInput): Promise<SchedulingSnapshot>;
  respond(actorId: string, accessToken: string, proposalId: string, input: SchedulingResponseInput): Promise<SchedulingSnapshot>;
  cancel(actorId: string, accessToken: string, proposalId: string, input: SchedulingMutation): Promise<SchedulingSnapshot>;
  feedback(actorId: string, accessToken: string, proposalId: string, input: SchedulingFeedbackInput): Promise<SchedulingSnapshot>;
  block(actorId: string, accessToken: string, friendId: string, input: SchedulingOperation): Promise<SchedulingSnapshot>;
  blockProposal(actorId: string, accessToken: string, proposalId: string, input: SchedulingOperation): Promise<SchedulingSnapshot>;
  report(actorId: string, accessToken: string, proposalId: string, input: SchedulingReportInput): Promise<SchedulingSnapshot>;
  reportFriend(actorId: string, accessToken: string, friendId: string, input: SchedulingReportInput): Promise<SchedulingSnapshot>;
  device(actorId: string, accessToken: string, input: SchedulingDeviceInput): Promise<SchedulingSnapshot>;
}
