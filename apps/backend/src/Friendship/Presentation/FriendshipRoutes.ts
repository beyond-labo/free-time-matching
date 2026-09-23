import { Hono, type Context } from "hono";
import type { AccessTokenVerifier } from "../../Auth/Application/Port/AccessTokenVerifier";
import { readBearerToken } from "../../Auth/Presentation/BearerToken";
import { InvalidRequestError, apiErrorResponse } from "../../Shared/Presentation/ApiError";
import type { ManageFriendships } from "../Application/UseCase/ManageFriendships";
import {
  isInviteCode,
  isUUID,
  isVersion,
  normalizeInviteCode,
  type FriendProfile,
  type FriendshipSnapshot,
} from "../Domain/Model/Friendship";

export interface FriendshipRouteDependencies {
  readonly tokenVerifier: AccessTokenVerifier;
  readonly manageFriendships: Pick<
    ManageFriendships,
    "snapshot" | "rotateCode" | "resolveCode" | "sendRequest" | "transitionRequest" | "removeFriend"
  >;
}

export const createFriendshipRoutes = (dependencies: FriendshipRouteDependencies) => {
  const routes = new Hono();

  routes.get("/friendships", (context) => authenticated(context, dependencies, async (actorId, token) =>
    context.json(projectSnapshot(await dependencies.manageFriendships.snapshot(actorId, token))),
  ));

  routes.post("/friendship-invite-code/rotate", (context) => authenticated(context, dependencies, async (actorId, token) =>
    context.json(projectSnapshot(await dependencies.manageFriendships.rotateCode(actorId, token))),
  ));

  routes.post("/friendship-invite-code/resolve", (context) => authenticated(context, dependencies, async (actorId, token) => {
    const { code } = await readCode(context.req.raw);
    return context.json({ candidate: projectProfile(await dependencies.manageFriendships.resolveCode(actorId, token, code)) });
  }));

  routes.post("/friendship-requests", (context) => authenticated(context, dependencies, async (actorId, token) => {
    const input = await readCodeAndOperation(context.req.raw);
    return context.json(projectSnapshot(await dependencies.manageFriendships.sendRequest(
      actorId,
      token,
      input.code,
      input.operationId,
    )));
  }));

  for (const transition of ["accept", "reject", "cancel"] as const) {
    routes.post(`/friendship-requests/:id/${transition}`, (context) => authenticated(context, dependencies, async (actorId, token) => {
      const requestId = requiredUUID(context.req.param("id"), "requestId");
      const mutation = await readMutation(context.req.raw);
      return context.json(projectSnapshot(await dependencies.manageFriendships.transitionRequest(
        actorId,
        token,
        requestId,
        transition,
        mutation.operationId,
        mutation.expectedVersion,
      )));
    }));
  }

  routes.delete("/friendships/:friendId", (context) => authenticated(context, dependencies, async (actorId, token) => {
    const friendId = requiredUUID(context.req.param("friendId"), "friendId");
    const mutation = await readMutation(context.req.raw);
    return context.json(projectSnapshot(await dependencies.manageFriendships.removeFriend(
      actorId,
      token,
      friendId,
      mutation.operationId,
      mutation.expectedVersion,
    )));
  }));

  return routes;
};

const authenticated = async (
  context: Context,
  dependencies: FriendshipRouteDependencies,
  operation: (actorId: string, accessToken: string) => Promise<Response>,
): Promise<Response> => {
  try {
    const accessToken = readBearerToken(context.req.header("authorization"));
    const actor = await dependencies.tokenVerifier.verify(accessToken);
    return await operation(actor.id, accessToken);
  } catch (error) {
    return apiErrorResponse(context, error);
  }
};

const readObject = async (request: Request): Promise<Record<string, unknown>> => {
  try {
    const input = await request.json() as unknown;
    if (typeof input !== "object" || input === null || Array.isArray(input)) throw new Error();
    return input as Record<string, unknown>;
  } catch {
    throw new InvalidRequestError("invalid_json", "JSON形式で入力してください。");
  }
};

const readCode = async (request: Request): Promise<{ code: string }> => {
  const input = await readObject(request);
  if (typeof input.code !== "string" || !isInviteCode(input.code)) {
    throw new InvalidRequestError("invalid_invite_code", "招待コードを確認してください。");
  }
  return { code: normalizeInviteCode(input.code) };
};

const readCodeAndOperation = async (request: Request) => {
  const input = await readObject(request);
  if (typeof input.code !== "string" || !isInviteCode(input.code)) {
    throw new InvalidRequestError("invalid_invite_code", "招待コードを確認してください。");
  }
  return {
    code: normalizeInviteCode(input.code),
    operationId: requiredUUID(input.operationId, "operationId"),
  };
};

const readMutation = async (request: Request) => {
  const input = await readObject(request);
  if (typeof input.expectedVersion !== "number" || !isVersion(input.expectedVersion)) {
    throw new InvalidRequestError("invalid_friendship_request", "versionを確認してください。");
  }
  return {
    operationId: requiredUUID(input.operationId, "operationId"),
    expectedVersion: input.expectedVersion,
  };
};

const requiredUUID = (value: unknown, field: string): string => {
  if (typeof value !== "string" || !isUUID(value)) {
    throw new InvalidRequestError("invalid_friendship_request", `${field}を確認してください。`);
  }
  return value;
};

const projectProfile = (profile: FriendProfile) => ({
  userId: profile.userId,
  nickname: profile.nickname,
  presetIconKey: profile.presetIconKey,
});

const projectSnapshot = (snapshot: FriendshipSnapshot) => ({
  inviteCode: snapshot.inviteCode,
  friends: snapshot.friends.map((friend) => ({
    profile: projectProfile(friend.profile),
    version: friend.version,
    createdAt: friend.createdAt,
  })),
  incomingRequests: snapshot.incomingRequests.map((request) => ({
    id: request.id,
    profile: projectProfile(request.profile),
    version: request.version,
    createdAt: request.createdAt,
  })),
  outgoingRequests: snapshot.outgoingRequests.map((request) => ({
    id: request.id,
    profile: projectProfile(request.profile),
    version: request.version,
    createdAt: request.createdAt,
  })),
});
