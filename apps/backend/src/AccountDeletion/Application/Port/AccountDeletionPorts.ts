import type {
  AccountDeletionRecord,
  AccountDeletionStatus,
  AccountDeletionStatusView,
} from "../../Domain/Model/AccountDeletion";

export interface AppleAuthorizationResult {
  readonly subject: string;
  readonly revocationToken: string;
  readonly tokenTypeHint: "refresh_token" | "access_token";
}

export interface AppleAuthorizationGateway {
  exchange(authorizationCode: string): Promise<AppleAuthorizationResult>;
  revoke(result: AppleAuthorizationResult): Promise<void>;
}

export interface CurrentIdentityGateway {
  appleSubject(accessToken: string): Promise<string>;
}

export interface AccountDeletionAdminPort {
  findByIdempotencyKey(
    userId: string,
    idempotencyKey: string,
  ): Promise<AccountDeletionRecord | null>;
  createAccepted(input: {
    userId: string;
    idempotencyKey: string;
    reference: string;
    statusTokenHash: string;
  }): Promise<AccountDeletionRecord>;
  setStatus(
    id: string,
    status: AccountDeletionStatus,
    message?: string,
  ): Promise<AccountDeletionRecord>;
  deleteAuthUser(userId: string): Promise<void>;
}

export interface AccountDeletionStatusPort {
  get(reference: string, statusToken: string): Promise<AccountDeletionStatusView | null>;
}

export interface StatusTokenIssuer {
  issue(reference: string): Promise<string>;
  hash(token: string): Promise<string>;
}

export class AppleReauthenticationError extends Error {
  constructor() {
    super("Apple reauthentication failed.");
    this.name = "AppleReauthenticationError";
  }
}

export class AccountDeletionNotFoundError extends Error {
  constructor() {
    super("The account deletion request was not found.");
    this.name = "AccountDeletionNotFoundError";
  }
}
