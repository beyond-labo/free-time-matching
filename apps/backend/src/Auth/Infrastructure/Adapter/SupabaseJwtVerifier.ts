import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import type { AccessTokenVerifier } from "../../Application/Port/AccessTokenVerifier";
import { InvalidAccessTokenError } from "../../Application/Port/AccessTokenVerifier";
import { isUuid, type AuthenticatedUser } from "../../Domain/AuthenticatedUser";

export interface SupabaseJwtVerifierConfiguration {
  readonly issuer: string;
  readonly jwksUrl: string;
  readonly audience?: string;
}

export class SupabaseJwtVerifier implements AccessTokenVerifier {
  private readonly jwks: JWTVerifyGetKey;

  constructor(
    private readonly configuration: SupabaseJwtVerifierConfiguration,
    jwks?: JWTVerifyGetKey,
  ) {
    this.jwks = jwks ?? createRemoteJWKSet(new URL(configuration.jwksUrl));
  }

  async verify(accessToken: string): Promise<AuthenticatedUser> {
    try {
      const result = await jwtVerify(accessToken, this.jwks, {
        issuer: this.configuration.issuer,
        audience: this.configuration.audience ?? "authenticated",
        algorithms: ["ES256", "RS256"],
      });

      const { sub, role, session_id: sessionId } = result.payload;
      if (!sub || !isUuid(sub) || role !== "authenticated") {
        throw new InvalidAccessTokenError();
      }
      if (sessionId !== undefined && typeof sessionId !== "string") {
        throw new InvalidAccessTokenError();
      }

      return { id: sub, sessionId };
    } catch (error) {
      if (error instanceof InvalidAccessTokenError) throw error;
      throw new InvalidAccessTokenError();
    }
  }
}
