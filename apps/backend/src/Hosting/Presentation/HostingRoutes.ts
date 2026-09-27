import { Hono, type Context } from "hono";
import type { AccessTokenVerifier } from "../../Auth/Application/Port/AccessTokenVerifier";
import { readBearerToken } from "../../Auth/Presentation/BearerToken";
import { InvalidRequestError, apiErrorResponse } from "../../Shared/Presentation/ApiError";
import type { HostingRepository } from "../Application/Port/HostingRepository";
import {
  HostingConflictError, HostingInvalidError, HostingUnavailableError, isUuid,
  type CreateHostingInput, type HostingInterval, type HostingMutationInput, type HostingResponseInput,
} from "../Domain/Hosting";

export interface HostingRouteDependencies {
  readonly tokenVerifier: AccessTokenVerifier;
  readonly hosting: HostingRepository;
}

export const createHostingRoutes = (dependencies: HostingRouteDependencies) => {
  const routes = new Hono();
  routes.post("/hostings", (context) => authenticated(context, dependencies, async (actorId, token) =>
    context.json({ hosting: await dependencies.hosting.create(actorId, token, await readCreate(context.req.raw)) }, 201)));
  routes.get("/hostings", (context) => authenticated(context, dependencies, async (actorId, token) =>
    context.json({ hostings: await dependencies.hosting.list(actorId, token) })));
  routes.get("/hostings/:id", (context) => authenticated(context, dependencies, async (actorId, token) => {
    const hosting = await dependencies.hosting.get(actorId, token, requiredUuid(context.req.param("id")));
    if (!hosting) throw new HostingUnavailableError();
    return context.json({ hosting });
  }));
  routes.put("/hostings/:id/response", (context) => authenticated(context, dependencies, async (actorId, token) =>
    context.json({ hosting: await dependencies.hosting.respond(actorId, token, requiredUuid(context.req.param("id")), await readResponse(context.req.raw)) })));
  routes.post("/hostings/:id/cancel", (context) => authenticated(context, dependencies, async (actorId, token) =>
    context.json({ hosting: await dependencies.hosting.cancel(actorId, token, requiredUuid(context.req.param("id")), await readMutation(context.req.raw)) })));
  return routes;
};

const authenticated = async (
  context: Context,
  dependencies: HostingRouteDependencies,
  operation: (actorId: string, accessToken: string) => Promise<Response>,
): Promise<Response> => {
  context.header("Cache-Control", "private, no-store");
  try {
    const accessToken = readBearerToken(context.req.header("authorization"));
    const actor = await dependencies.tokenVerifier.verify(accessToken);
    return await operation(actor.id, accessToken);
  } catch (error) {
    if (error instanceof HostingConflictError) return context.json({ error: { code: "hosting_conflict", message: "募集の状態が変わりました。最新の状態を確認してください。" } }, 409);
    if (error instanceof HostingUnavailableError) return context.json({ error: { code: "hosting_unavailable", message: "この募集は利用できません。" } }, 404);
    if (error instanceof HostingInvalidError) return context.json({ error: { code: "hosting_invalid", message: "募集内容を確認してください。" } }, 400);
    return apiErrorResponse(context, error);
  }
};

const readObject = async (request: Request): Promise<Record<string, unknown>> => {
  let value: unknown;
  try { value = await request.json(); } catch { throw new InvalidRequestError("invalid_json", "JSON形式で入力してください。"); }
  if (!isObject(value)) throw new InvalidRequestError("invalid_hosting", "募集内容を確認してください。");
  return value;
};
const isObject = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const requiredUuid = (value: unknown): string => {
  if (!isUuid(value)) throw new InvalidRequestError("invalid_hosting", "IDを確認してください。");
  return value;
};
const requiredVersion = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) throw new InvalidRequestError("invalid_hosting", "versionを確認してください。");
  return value;
};
const requiredInstant = (value: unknown): string => {
  if (typeof value !== "string" || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$/.test(value)) {
    throw new InvalidRequestError("invalid_hosting", "日時を確認してください。");
  }
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp) || timestamp % 900000 !== 0 || /\.(?!0+(?:Z|[+-]))\d+/.test(value)) {
    throw new InvalidRequestError("invalid_hosting", "15分単位の日時を指定してください。");
  }
  return new Date(timestamp).toISOString();
};
const readInterval = (value: unknown): HostingInterval => {
  if (!isObject(value)) throw new InvalidRequestError("invalid_hosting", "時間を確認してください。");
  const start = requiredInstant(value.start);
  const end = requiredInstant(value.end);
  if (start >= end) throw new InvalidRequestError("invalid_hosting", "開始と終了を確認してください。");
  return { start, end };
};
const readCreate = async (request: Request): Promise<CreateHostingInput> => {
  const value = await readObject(request);
  const interval = readInterval(value);
  if (value.mode !== "online" && value.mode !== "offline") throw new InvalidRequestError("invalid_hosting", "開催形態を確認してください。");
  if (value.mode === "offline" && value.area !== "shinjuku" && value.area !== "shibuya" && value.area !== "discussLater") {
    throw new InvalidRequestError("invalid_hosting", "エリアを確認してください。");
  }
  if (value.mode === "online" && value.area !== undefined && value.area !== null) throw new InvalidRequestError("invalid_hosting", "オンライン募集にエリアは指定できません。");
  if (value.category !== undefined && value.category !== null && !["game", "meal", "call", "work"].includes(value.category as string)) {
    throw new InvalidRequestError("invalid_hosting", "カテゴリを確認してください。");
  }
  if (!Array.isArray(value.targets) || value.targets.length === 0 || value.targets.length > 50) throw new InvalidRequestError("invalid_hosting", "招待先を1〜50人選んでください。");
  const targets = value.targets.map((target: unknown) => {
    if (!isObject(target) || target.type !== "friend") throw new InvalidRequestError("invalid_hosting", "招待先を確認してください。");
    return { type: "friend" as const, id: requiredUuid(target.id) };
  });
  if (new Set(targets.map((target) => target.id)).size !== targets.length) throw new InvalidRequestError("invalid_hosting", "同じ友達を重複指定できません。");
  if (!isObject(value.availabilityMetadata)) throw new InvalidRequestError("invalid_hosting", "暇時間の属性を確認してください。");
  const metadata = value.availabilityMetadata;
  if (metadata.category !== undefined && metadata.category !== null && !["game", "meal", "call", "work"].includes(metadata.category as string)) {
    throw new InvalidRequestError("invalid_hosting", "暇時間のカテゴリを確認してください。");
  }
  if (metadata.visibility !== "privateUntilAccepted" && metadata.visibility !== "shareOnHosting") throw new InvalidRequestError("invalid_hosting", "共有設定を確認してください。");
  return {
    ...interval,
    mode: value.mode,
    area: value.mode === "online" ? null : value.area as CreateHostingInput["area"],
    category: (value.category ?? null) as CreateHostingInput["category"],
    targets,
    availabilityMetadata: { category: (metadata.category ?? null) as CreateHostingInput["category"], visibility: metadata.visibility },
    operationId: requiredUuid(value.operationId),
  };
};
const readMutation = async (request: Request): Promise<HostingMutationInput> => {
  const value = await readObject(request);
  return { operationId: requiredUuid(value.operationId), expectedVersion: requiredVersion(value.expectedVersion) };
};
const readResponse = async (request: Request): Promise<HostingResponseInput> => {
  const value = await readObject(request);
  if (value.status !== "accepted" && value.status !== "declined") throw new InvalidRequestError("invalid_hosting", "回答を確認してください。");
  if (!Array.isArray(value.intervals)) throw new InvalidRequestError("invalid_hosting", "回答時間を確認してください。");
  const intervals = value.intervals.map(readInterval);
  if ((value.status === "accepted" && intervals.length === 0) || (value.status === "declined" && intervals.length !== 0)) {
    throw new InvalidRequestError("invalid_hosting", "回答時間を確認してください。");
  }
  return { ...(await readMutationFromObject(value)), status: value.status, intervals };
};
const readMutationFromObject = async (value: Record<string, unknown>): Promise<HostingMutationInput> =>
  ({ operationId: requiredUuid(value.operationId), expectedVersion: requiredVersion(value.expectedVersion) });
