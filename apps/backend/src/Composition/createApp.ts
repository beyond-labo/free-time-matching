import { Hono } from "hono";
import { healthRoute } from "../Health/Presentation/healthRoute";
import type { AccessTokenVerifier } from "../Auth/Application/Port/AccessTokenVerifier";
import { SupabaseJwtVerifier } from "../Auth/Infrastructure/Adapter/SupabaseJwtVerifier";
import { ManageProfile } from "../User/Application/UseCase/ManageProfile";
import { SupabaseProfileRepository } from "../User/Infrastructure/Repository/SupabaseProfileRepository";
import { createUserRoutes } from "../User/Presentation/UserRoutes";
import type { AccountDeletionStatusPort } from "../AccountDeletion/Application/Port/AccountDeletionPorts";
import { RequestAccountDeletion } from "../AccountDeletion/Application/UseCase/RequestAccountDeletion";
import { AppleOAuthGateway } from "../AccountDeletion/Infrastructure/Adapter/AppleOAuthGateway";
import { HmacStatusTokenIssuer } from "../AccountDeletion/Infrastructure/Adapter/HmacStatusTokenIssuer";
import { SupabaseCurrentIdentityGateway } from "../AccountDeletion/Infrastructure/Adapter/SupabaseCurrentIdentityGateway";
import {
  SupabaseDeletionAdminAdapter,
  SupabaseDeletionStatusAdapter,
} from "../AccountDeletion/Infrastructure/Adapter/SupabaseDeletionAdminAdapter";
import { createAccountDeletionRoutes } from "../AccountDeletion/Presentation/AccountDeletionRoutes";
import { ManageFriendships } from "../Friendship/Application/UseCase/ManageFriendships";
import { SupabaseFriendshipRepository } from "../Friendship/Infrastructure/Repository/SupabaseFriendshipRepository";
import { createFriendshipRoutes } from "../Friendship/Presentation/FriendshipRoutes";
import type { AvailabilityRepository } from "../Availability/Application/Port/AvailabilityRepository";
import { SupabaseAvailabilityRepository } from "../Availability/Infrastructure/Repository/SupabaseAvailabilityRepository";
import { createAvailabilityRoutes } from "../Availability/Presentation/AvailabilityRoutes";

export interface BackendBindings {
  readonly SUPABASE_URL?: string;
  readonly SUPABASE_PUBLISHABLE_KEY?: string;
  readonly SUPABASE_SECRET_KEY?: string;
  readonly APPLE_CLIENT_ID?: string;
  readonly APPLE_TEAM_ID?: string;
  readonly APPLE_KEY_ID?: string;
  readonly APPLE_PRIVATE_KEY?: string;
  readonly ACCOUNT_DELETION_STATUS_SECRET?: string;
}

export interface AppDependencies {
  readonly tokenVerifier: AccessTokenVerifier;
  readonly manageProfile: Pick<ManageProfile, "get" | "put">;
  readonly manageFriendships: Pick<
    ManageFriendships,
    "snapshot" | "rotateCode" | "resolveCode" | "sendRequest" | "transitionRequest" | "removeFriend"
  >;
  readonly requestDeletion: Pick<RequestAccountDeletion, "execute">;
  readonly deletionStatus: AccountDeletionStatusPort;
  readonly availability?: AvailabilityRepository;
}

export const createApp = (
  bindings: BackendBindings = {},
  injectedDependencies?: AppDependencies,
) => {
  const app = new Hono();
  app.use("*", async (context, next) => {
    if (!/^\/v1\/availability(?:\/|$)/.test(context.req.path)) return next();
    const requestId = crypto.randomUUID();
    const started = performance.now();
    await next();
    context.header("X-Request-ID", requestId);
    console.info(JSON.stringify({
      event: "availability_request",
      requestId,
      method: context.req.method,
      status: context.res.status,
      durationMs: Math.round(performance.now() - started),
    }));
  });
  let runtimeDependencies: AppDependencies | undefined;
  const dependencies = (): AppDependencies => {
    runtimeDependencies ??= injectedDependencies ?? createRuntimeDependencies(bindings);
    return runtimeDependencies;
  };

  const lazyTokenVerifier: AccessTokenVerifier = {
    verify: (token) => dependencies().tokenVerifier.verify(token),
  };
  const lazyProfile: Pick<ManageProfile, "get" | "put"> = {
    get: (userId: string, token: string) =>
      dependencies().manageProfile.get(userId, token),
    put: (userId: string, token: string, input: Parameters<ManageProfile["put"]>[2]) =>
      dependencies().manageProfile.put(userId, token, input),
  };
  const lazyDeletion: Pick<RequestAccountDeletion, "execute"> = {
    execute: (input: Parameters<RequestAccountDeletion["execute"]>[0]) =>
      dependencies().requestDeletion.execute(input),
  };
  const lazyDeletionStatus: AccountDeletionStatusPort = {
    get: (reference, token) => dependencies().deletionStatus.get(reference, token),
  };
  const lazyFriendships: AppDependencies["manageFriendships"] = {
    snapshot: (actorId, token) => dependencies().manageFriendships.snapshot(actorId, token),
    rotateCode: (actorId, token) => dependencies().manageFriendships.rotateCode(actorId, token),
    resolveCode: (actorId, token, code) => dependencies().manageFriendships.resolveCode(actorId, token, code),
    sendRequest: (actorId, token, code, operationId) =>
      dependencies().manageFriendships.sendRequest(actorId, token, code, operationId),
    transitionRequest: (actorId, token, requestId, transition, operationId, expectedVersion) =>
      dependencies().manageFriendships.transitionRequest(
        actorId,
        token,
        requestId,
        transition,
        operationId,
        expectedVersion,
      ),
    removeFriend: (actorId, token, friendId, operationId, expectedVersion) =>
      dependencies().manageFriendships.removeFriend(
        actorId,
        token,
        friendId,
        operationId,
        expectedVersion,
      ),
  };
  const lazyAvailability: AvailabilityRepository = {
    list: (actorId, token) => dependencies().availability!.list(actorId, token),
    upsert: (actorId, token, id, input) => dependencies().availability!.upsert(actorId, token, id, input),
    remove: (actorId, token, id) => dependencies().availability!.remove(actorId, token, id),
  };

  app.get("/healthz", healthRoute);
  app.route(
    "/v1",
    createUserRoutes({ tokenVerifier: lazyTokenVerifier, manageProfile: lazyProfile }),
  );
  app.route(
    "/v1",
    createFriendshipRoutes({
      tokenVerifier: lazyTokenVerifier,
      manageFriendships: lazyFriendships,
    }),
  );
  app.route("/v1", createAvailabilityRoutes({ tokenVerifier: lazyTokenVerifier, availability: lazyAvailability }));
  app.route(
    "/v1",
    createAccountDeletionRoutes({
      tokenVerifier: lazyTokenVerifier,
      requestDeletion: lazyDeletion,
      deletionStatus: lazyDeletionStatus,
    }),
  );
  app.notFound(() => new Response(null, { status: 404 }));

  return app;
};

const createRuntimeDependencies = (bindings: BackendBindings): AppDependencies => {
  const supabaseUrl = requireBinding(bindings, "SUPABASE_URL");
  const publishableKey = requireBinding(bindings, "SUPABASE_PUBLISHABLE_KEY");
  const userConfiguration = { url: supabaseUrl, apiKey: publishableKey };
  const statusTokens = new HmacStatusTokenIssuer(
    requireBinding(bindings, "ACCOUNT_DELETION_STATUS_SECRET"),
  );

  // The broad Supabase secret is constructed only inside the account-deletion
  // adapter. Normal profile reads and writes always carry the user's JWT and
  // publishable key so Postgres RLS remains authoritative.
  const deletionAdmin = new SupabaseDeletionAdminAdapter(
    supabaseUrl,
    requireBinding(bindings, "SUPABASE_SECRET_KEY"),
  );
  const apple = new AppleOAuthGateway({
    clientId: requireBinding(bindings, "APPLE_CLIENT_ID"),
    teamId: requireBinding(bindings, "APPLE_TEAM_ID"),
    keyId: requireBinding(bindings, "APPLE_KEY_ID"),
    privateKey: requireBinding(bindings, "APPLE_PRIVATE_KEY"),
  });

  return {
    tokenVerifier: new SupabaseJwtVerifier(deriveSupabaseAuthConfiguration(supabaseUrl)),
    manageProfile: new ManageProfile(new SupabaseProfileRepository(userConfiguration)),
    manageFriendships: new ManageFriendships(
      new SupabaseFriendshipRepository(userConfiguration),
    ),
    requestDeletion: new RequestAccountDeletion(
      deletionAdmin,
      apple,
      new SupabaseCurrentIdentityGateway(userConfiguration),
      statusTokens,
    ),
    deletionStatus: new SupabaseDeletionStatusAdapter(userConfiguration),
    availability: new SupabaseAvailabilityRepository(userConfiguration),
  };
};

export const deriveSupabaseAuthConfiguration = (supabaseUrl: string) => {
  const projectUrl = new URL(supabaseUrl);
  const isLocalHttp =
    projectUrl.protocol === "http:" &&
    (projectUrl.hostname === "127.0.0.1" || projectUrl.hostname === "localhost");
  if (projectUrl.protocol !== "https:" && !isLocalHttp) {
    throw new Error("SUPABASE_URL must use HTTPS outside local development.");
  }
  const baseUrl = projectUrl.toString().replace(/\/$/, "");
  const issuer = `${baseUrl}/auth/v1`;
  return {
    issuer,
    jwksUrl: `${issuer}/.well-known/jwks.json`,
  };
};

const requireBinding = <Key extends keyof BackendBindings>(
  bindings: BackendBindings,
  key: Key,
): string => {
  const value = bindings[key];
  if (!value) throw new Error(`Missing Worker binding: ${key}`);
  return value;
};
