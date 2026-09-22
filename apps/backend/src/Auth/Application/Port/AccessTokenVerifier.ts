import type { AuthenticatedUser } from "../../Domain/AuthenticatedUser";

export interface AccessTokenVerifier {
  verify(accessToken: string): Promise<AuthenticatedUser>;
}

export class InvalidAccessTokenError extends Error {
  constructor() {
    super("The access token is invalid.");
    this.name = "InvalidAccessTokenError";
  }
}
