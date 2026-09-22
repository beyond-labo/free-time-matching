import type { CurrentIdentityGateway } from "../../Application/Port/AccountDeletionPorts";
import { AppleReauthenticationError } from "../../Application/Port/AccountDeletionPorts";
import {
  supabaseFetch,
  type SupabaseRestConfiguration,
} from "../../../Shared/Infrastructure/SupabaseRestClient";

interface SupabaseIdentity {
  provider?: string;
  provider_id?: string;
  identity_data?: { sub?: string };
}

export class SupabaseCurrentIdentityGateway implements CurrentIdentityGateway {
  constructor(private readonly configuration: SupabaseRestConfiguration) {}

  async appleSubject(accessToken: string): Promise<string> {
    try {
      const response = await supabaseFetch(
        this.configuration,
        "/auth/v1/user",
        { method: "GET" },
        accessToken,
      );
      const user = (await response.json()) as { identities?: SupabaseIdentity[] };
      const apple = user.identities?.find((identity) => identity.provider === "apple");
      const subject = apple?.identity_data?.sub ?? apple?.provider_id;
      if (!subject) throw new AppleReauthenticationError();
      return subject;
    } catch {
      throw new AppleReauthenticationError();
    }
  }
}
