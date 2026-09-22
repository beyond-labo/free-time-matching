import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "jose";
import type {
  AppleAuthorizationGateway,
  AppleAuthorizationResult,
} from "../../Application/Port/AccountDeletionPorts";
import { AppleReauthenticationError } from "../../Application/Port/AccountDeletionPorts";

export interface AppleOAuthConfiguration {
  readonly clientId: string;
  readonly teamId: string;
  readonly keyId: string;
  readonly privateKey: string;
  readonly baseUrl?: string;
  readonly jwksUrl?: string;
}

interface AppleTokenResponse {
  access_token?: string;
  refresh_token?: string;
  id_token?: string;
}

export class AppleOAuthGateway implements AppleAuthorizationGateway {
  private readonly baseUrl: string;
  private readonly jwks: ReturnType<typeof createRemoteJWKSet>;

  constructor(private readonly configuration: AppleOAuthConfiguration) {
    this.baseUrl = configuration.baseUrl ?? "https://appleid.apple.com";
    this.jwks = createRemoteJWKSet(
      new URL(configuration.jwksUrl ?? "https://appleid.apple.com/auth/keys"),
    );
  }

  async exchange(authorizationCode: string): Promise<AppleAuthorizationResult> {
    try {
      const clientSecret = await this.createClientSecret();
      const response = await fetch(`${this.baseUrl}/auth/token`, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: this.configuration.clientId,
          client_secret: clientSecret,
          code: authorizationCode,
          grant_type: "authorization_code",
        }),
      });
      if (!response.ok) throw new AppleReauthenticationError();
      const tokens = (await response.json()) as AppleTokenResponse;
      if (!tokens.id_token) throw new AppleReauthenticationError();
      const verified = await jwtVerify(tokens.id_token, this.jwks, {
        issuer: "https://appleid.apple.com",
        audience: this.configuration.clientId,
        algorithms: ["RS256"],
      });
      if (!verified.payload.sub) throw new AppleReauthenticationError();

      if (tokens.refresh_token) {
        return {
          subject: verified.payload.sub,
          revocationToken: tokens.refresh_token,
          tokenTypeHint: "refresh_token",
        };
      }
      if (tokens.access_token) {
        return {
          subject: verified.payload.sub,
          revocationToken: tokens.access_token,
          tokenTypeHint: "access_token",
        };
      }
      throw new AppleReauthenticationError();
    } catch (error) {
      if (error instanceof AppleReauthenticationError) throw error;
      throw new AppleReauthenticationError();
    }
  }

  async revoke(result: AppleAuthorizationResult): Promise<void> {
    const response = await fetch(`${this.baseUrl}/auth/revoke`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: this.configuration.clientId,
        client_secret: await this.createClientSecret(),
        token: result.revocationToken,
        token_type_hint: result.tokenTypeHint,
      }),
    });
    if (!response.ok) throw new Error("Apple token revocation failed.");
  }

  private async createClientSecret(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    const privateKey = await importPKCS8(
      this.configuration.privateKey.replaceAll("\\n", "\n"),
      "ES256",
    );
    return new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: this.configuration.keyId })
      .setIssuer(this.configuration.teamId)
      .setSubject(this.configuration.clientId)
      .setAudience("https://appleid.apple.com")
      .setIssuedAt(now)
      .setExpirationTime(now + 300)
      .sign(privateKey);
  }
}
