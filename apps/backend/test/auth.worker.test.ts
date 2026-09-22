import {
  SignJWT,
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
} from "jose";
import { beforeAll, describe, expect, it } from "vitest";
import { InvalidAccessTokenError } from "../src/Auth/Application/Port/AccessTokenVerifier";
import { SupabaseJwtVerifier } from "../src/Auth/Infrastructure/Adapter/SupabaseJwtVerifier";
import { deriveSupabaseAuthConfiguration } from "../src/Composition/createApp";

const issuer = "https://project-ref.supabase.co/auth/v1";
const subject = "8e26166a-a14a-4933-a953-199798829ab5";
let privateKey: CryptoKey;
let verifier: SupabaseJwtVerifier;

beforeAll(async () => {
  const pair = await generateKeyPair("ES256", { extractable: true });
  privateKey = pair.privateKey;
  const publicJwk = await exportJWK(pair.publicKey);
  publicJwk.kid = "test-key";
  publicJwk.alg = "ES256";
  verifier = new SupabaseJwtVerifier(
    {
      issuer,
      jwksUrl: `${issuer}/.well-known/jwks.json`,
    },
    createLocalJWKSet({ keys: [publicJwk] }),
  );
});

const token = async (overrides: {
  issuer?: string;
  audience?: string;
  role?: string;
  subject?: string;
  expiration?: string;
} = {}) =>
  new SignJWT({ role: overrides.role ?? "authenticated", session_id: "session-1" })
    .setProtectedHeader({ alg: "ES256", kid: "test-key" })
    .setIssuer(overrides.issuer ?? issuer)
    .setAudience(overrides.audience ?? "authenticated")
    .setSubject(overrides.subject ?? subject)
    .setIssuedAt()
    .setExpirationTime(overrides.expiration ?? "5m")
    .sign(privateKey);

describe("SupabaseJwtVerifier", () => {
  it("accepts a signed authenticated Supabase token", async () => {
    await expect(verifier.verify(await token())).resolves.toEqual({
      id: subject,
      sessionId: "session-1",
    });
  });

  it.each([
    { issuer: "https://attacker.example/auth/v1" },
    { audience: "other" },
    { role: "service_role" },
    { subject: "not-a-uuid" },
    { expiration: "0s" },
  ])("rejects invalid claims: %o", async (overrides) => {
    await expect(verifier.verify(await token(overrides))).rejects.toBeInstanceOf(
      InvalidAccessTokenError,
    );
  });
});

describe("Supabase auth endpoint configuration", () => {
  it("derives issuer and JWKS from the trusted project origin", () => {
    expect(deriveSupabaseAuthConfiguration("https://project-ref.supabase.co/")).toEqual({
      issuer: "https://project-ref.supabase.co/auth/v1",
      jwksUrl: "https://project-ref.supabase.co/auth/v1/.well-known/jwks.json",
    });
  });

  it("rejects cleartext non-local project URLs", () => {
    expect(() => deriveSupabaseAuthConfiguration("http://attacker.example")).toThrow(
      "SUPABASE_URL must use HTTPS",
    );
  });
});
