import type { CreateHostingInput, HostingMutationInput, HostingProjection, HostingResponseInput } from "../../Domain/Hosting";

export interface HostingRepository {
  create(actorId: string, accessToken: string, input: CreateHostingInput): Promise<HostingProjection>;
  list(actorId: string, accessToken: string): Promise<HostingProjection[]>;
  get(actorId: string, accessToken: string, hostingId: string): Promise<HostingProjection | null>;
  respond(actorId: string, accessToken: string, hostingId: string, input: HostingResponseInput): Promise<HostingProjection>;
  cancel(actorId: string, accessToken: string, hostingId: string, input: HostingMutationInput): Promise<HostingProjection>;
}
