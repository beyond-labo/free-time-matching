import { Hono, type Context } from "hono";
import type { AccessTokenVerifier } from "../../Auth/Application/Port/AccessTokenVerifier";
import { readBearerToken } from "../../Auth/Presentation/BearerToken";
import { apiErrorResponse, InvalidRequestError } from "../../Shared/Presentation/ApiError";
import type { AvailabilityRepository } from "../Application/Port/AvailabilityRepository";
import {
  AvailabilityConflictError,
  AvailabilityHostingConflictError,
  AvailabilityUnavailableError,
  isAvailabilityCategory,
  isAvailabilityVisibility,
  isUuid,
  type AvailabilityInput,
  type AvailabilityIntervalOperation,
} from "../Domain/Model/Availability";

export interface AvailabilityRouteDependencies {
  readonly tokenVerifier: AccessTokenVerifier;
  readonly availability: AvailabilityRepository;
}

export const createAvailabilityRoutes = (dependencies: AvailabilityRouteDependencies) => {
  const routes = new Hono();
  routes.get("/availability", (context) => authenticated(context, dependencies, async (actorId, token) =>
    context.json({ slots: await dependencies.availability.list(actorId, token) }),
  ));
  routes.put("/availability/:id", (context) => authenticated(context, dependencies, async (actorId, token) => {
    const id = requiredUuid(context.req.param("id"));
    const input = await readInput(context.req.raw);
    return context.json({ slot: await dependencies.availability.upsert(actorId, token, id, input) });
  }));
  routes.delete("/availability/:id", (context) => authenticated(context, dependencies, async (actorId, token) => {
    const id = requiredUuid(context.req.param("id"));
    await dependencies.availability.remove(actorId, token, id);
    return new Response(null, { status: 204 });
  }));
  routes.post("/availability/intervals:union", (context) => authenticated(context, dependencies, async (actorId, token) => {
    const input = await readIntervalOperation(context.req.raw, true) as AvailabilityIntervalOperation;
    return context.json({ slots: await dependencies.availability.union(actorId, token, input) });
  }));
  routes.post("/availability/intervals:subtract", (context) => authenticated(context, dependencies, async (actorId, token) => {
    const input = await readIntervalOperation(context.req.raw, false);
    return context.json({ slots: await dependencies.availability.subtract(actorId, token, input) });
  }));
  return routes;
};

const authenticated = async (
  context: Context,
  dependencies: AvailabilityRouteDependencies,
  operation: (actorId: string, token: string) => Promise<Response>,
): Promise<Response> => {
  context.header("Cache-Control", "private, no-store");
  try {
    const token = readBearerToken(context.req.header("authorization"));
    const actor = await dependencies.tokenVerifier.verify(token);
    return await operation(actor.id, token);
  } catch (error) {
    if (error instanceof AvailabilityConflictError) {
      return context.json({ error: { code: "availability_conflict", message: "登録時間が既存の暇時間と重なっています。" } }, 409);
    }
    if (error instanceof AvailabilityHostingConflictError) {
      return context.json({ error: { code: "availability_hosting_conflict", message: "募集中の時間は削除できません。先に募集を取り消してください。" } }, 409);
    }
    if (error instanceof AvailabilityUnavailableError) {
      return context.json({ error: { code: "availability_unavailable", message: "暇時間を保存できません。" } }, 400);
    }
    return apiErrorResponse(context, error);
  }
};

const readIntervalOperation = async (request: Request, includeAttributes: boolean): Promise<{
  start: string; end: string; operationId: string;
  category?: AvailabilityInput["category"];
  visibility?: AvailabilityInput["visibility"];
}> => {
  let value: unknown;
  try { value = await request.json(); } catch { throw new InvalidRequestError("invalid_json", "JSON形式で入力してください。"); }
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new InvalidRequestError("invalid_availability", "暇時間を確認してください。");
  const input = value as Record<string, unknown>;
  if (!isUuid(input.operationId)) throw new InvalidRequestError("invalid_availability", "operationIdはUUIDで指定してください。");
  if (!isInstant(input.start) || !isInstant(input.end)) throw new InvalidRequestError("invalid_availability", "startとendはUTCの日時を指定してください。");
  if (includeAttributes && !isAvailabilityCategory(input.category) && input.category !== null && input.category !== undefined) throw new InvalidRequestError("invalid_availability", "categoryを確認してください。");
  if (includeAttributes && !isAvailabilityVisibility(input.visibility ?? "privateUntilAccepted")) throw new InvalidRequestError("invalid_availability", "visibilityを確認してください。");
  const start = new Date(input.start);
  const end = new Date(input.end);
  if (start >= end || start.getTime() % 900000 !== 0 || end.getTime() % 900000 !== 0) {
    throw new InvalidRequestError("invalid_availability", "開始・終了を15分単位で指定してください。");
  }
  return {
    start: start.toISOString(), end: end.toISOString(), operationId: input.operationId,
    ...(includeAttributes ? {
      category: input.category === undefined ? null : input.category as AvailabilityInput["category"],
      visibility: (input.visibility ?? "privateUntilAccepted") as AvailabilityInput["visibility"],
    } : {}),
  };
};

const requiredUuid = (value: string): string => {
  if (!isUuid(value)) throw new InvalidRequestError("invalid_availability", "idを確認してください。");
  return value;
};

const readInput = async (request: Request): Promise<AvailabilityInput> => {
  let value: unknown;
  try { value = await request.json(); } catch { throw new InvalidRequestError("invalid_json", "JSON形式で入力してください。"); }
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new InvalidRequestError("invalid_availability", "暇時間を確認してください。");
  }
  const input = value as Record<string, unknown>;
  if (!isInstant(input.start) || !isInstant(input.end)) throw new InvalidRequestError("invalid_availability", "startとendはUTCの日時を指定してください。");
  if (!isAvailabilityCategory(input.category) && input.category !== null && input.category !== undefined) {
    throw new InvalidRequestError("invalid_availability", "categoryを確認してください。");
  }
  if (!isAvailabilityVisibility(input.visibility ?? "privateUntilAccepted")) {
    throw new InvalidRequestError("invalid_availability", "visibilityを確認してください。");
  }
  const start = new Date(input.start as string);
  const end = new Date(input.end as string);
  const now = Date.now();
  if (start.getTime() >= end.getTime() || start.getTime() < now || end.getTime() > now + 14 * 24 * 60 * 60 * 1000 || start.getTime() % 900000 !== 0 || end.getTime() % 900000 !== 0) {
    throw new InvalidRequestError("invalid_availability", "15分単位で現在から14日以内の時間を指定してください。");
  }
  return {
    start: start.toISOString(),
    end: end.toISOString(),
    category: input.category === undefined ? null : input.category as AvailabilityInput["category"],
    visibility: (input.visibility ?? "privateUntilAccepted") as AvailabilityInput["visibility"],
  };
};

const isInstant = (value: unknown): value is string =>
  typeof value === "string" && /T.*(?:Z|[+-]\d{2}:?\d{2})$/.test(value) && !Number.isNaN(Date.parse(value));
