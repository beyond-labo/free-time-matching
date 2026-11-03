import { Hono, type Context } from "hono";
import type { AccessTokenVerifier } from "../../../Auth/Application/Port/AccessTokenVerifier";
import { readBearerToken } from "../../../Auth/Presentation/BearerToken";
import { InvalidRequestError, apiErrorResponse } from "../../../Shared/Presentation/ApiError";
import type { AutomaticSchedulingRepository } from "../../Application/Port/AutomaticSchedulingRepository";
import {
  SchedulingConflictError, SchedulingInvalidError, SchedulingUnavailableError, isSchedulingUuid,
  type SchedulingSnapshot, type SchedulingOperation, type SchedulingMutation, type SchedulingSettingsInput,
  type SchedulingResponseInput, type SchedulingFeedbackInput, type SchedulingReportInput, type SchedulingDeviceInput,
} from "../../Domain/Model/AutomaticScheduling";

interface SchedulingRouteDependencies {
  readonly tokenVerifier: AccessTokenVerifier;
  readonly automaticScheduling: AutomaticSchedulingRepository;
}
export const createAutomaticSchedulingRoutes = (dependencies: SchedulingRouteDependencies) => {
  const routes = new Hono();
  const path = "/automatic-scheduling";
  const authenticated = async (context: Context, action: (actor: string, token: string) => Promise<SchedulingSnapshot>): Promise<Response> => {
    context.header("Cache-Control", "private, no-store");
    try {
      const token = readBearerToken(context.req.header("authorization"));
      const actor = await dependencies.tokenVerifier.verify(token);
      return context.json(await action(actor.id, token));
    } catch (error) {
      if (error instanceof SchedulingConflictError) return context.json({ error: {
        code: "automatic_scheduling_conflict", message: "状態が変わりました。最新の状態を確認してください。",
      } }, 409);
      if (error instanceof SchedulingUnavailableError) return context.json({ error: {
        code: "automatic_scheduling_unavailable", message: "この操作は利用できません。",
      } }, 404);
      if (error instanceof SchedulingInvalidError) return context.json({ error: {
        code: "automatic_scheduling_invalid", message: "入力内容を確認してください。",
      } }, 400);
      return apiErrorResponse(context, error);
    }
  };
  const repository = dependencies.automaticScheduling;
  routes.get(path, (c) => authenticated(c, (actor, token) => repository.snapshot(actor, token)));
  routes.put(`${path}/settings`, (c) => authenticated(c, async (actor, token) =>
    repository.settings(actor, token, readSettings(await readObject(c.req.raw)))));
  routes.put(`${path}/permissions/:friendId`, (c) => authenticated(c, async (actor, token) =>
    repository.permission(actor, token, requiredUuid(c.req.param("friendId")), readSettings(await readObject(c.req.raw)))));
  routes.put(`${path}/proposals/:id/response`, (c) => authenticated(c, async (actor, token) =>
    repository.respond(actor, token, requiredUuid(c.req.param("id")), readResponse(await readObject(c.req.raw)))));
  routes.post(`${path}/proposals/:id/cancel`, (c) => authenticated(c, async (actor, token) =>
    repository.cancel(actor, token, requiredUuid(c.req.param("id")), readMutation(await readObject(c.req.raw)))));
  routes.put(`${path}/proposals/:id/feedback`, (c) => authenticated(c, async (actor, token) =>
    repository.feedback(actor, token, requiredUuid(c.req.param("id")), readFeedback(await readObject(c.req.raw)))));
  routes.post(`${path}/blocks/:friendId`, (c) => authenticated(c, async (actor, token) =>
    repository.block(actor, token, requiredUuid(c.req.param("friendId")), readOperation(await readObject(c.req.raw)))));
  routes.post(`${path}/proposals/:id/block`, (c) => authenticated(c, async (actor, token) =>
    repository.blockProposal(actor, token, requiredUuid(c.req.param("id")), readOperation(await readObject(c.req.raw)))));
  routes.post(`${path}/proposals/:id/report`, (c) => authenticated(c, async (actor, token) =>
    repository.report(actor, token, requiredUuid(c.req.param("id")), readReport(await readObject(c.req.raw)))));
  routes.post(`${path}/reports/:friendId`, (c) => authenticated(c, async (actor, token) =>
    repository.reportFriend(actor, token, requiredUuid(c.req.param("friendId")), readReport(await readObject(c.req.raw)))));
  routes.put(`${path}/device`, (c) => authenticated(c, async (actor, token) =>
    repository.device(actor, token, readDevice(await readObject(c.req.raw)))));
  return routes;
};

const invalid = (): never => { throw new InvalidRequestError("automatic_scheduling_invalid", "入力内容を確認してください。"); };
const readObject = async (request: Request): Promise<Record<string, unknown>> => {
  let value: unknown;
  try { value = await request.json(); } catch { throw new InvalidRequestError("invalid_json", "JSON形式で入力してください。"); }
  if (!value || typeof value !== "object" || Array.isArray(value)) return invalid();
  return value as Record<string, unknown>;
};
const requiredUuid = (value: unknown): string => isSchedulingUuid(value) ? value : invalid();
const requiredBoolean = (value: unknown): boolean => typeof value === "boolean" ? value : invalid();
const readOperation = (row: Record<string, unknown>): SchedulingOperation => ({ operationId: requiredUuid(row.operationId) });
const readMutation = (row: Record<string, unknown>): SchedulingMutation => {
  if (typeof row.expectedVersion !== "number" || !Number.isSafeInteger(row.expectedVersion) || row.expectedVersion < 1) return invalid();
  return { ...readOperation(row), expectedVersion: row.expectedVersion };
};
const readSettings = (row: Record<string, unknown>): SchedulingSettingsInput => ({ ...readOperation(row), enabled: requiredBoolean(row.enabled) });
const readResponse = (row: Record<string, unknown>): SchedulingResponseInput => {
  if (row.response !== "accepted" && row.response !== "declined") return invalid();
  const shareAcceptance = requiredBoolean(row.shareAcceptance);
  if (row.response === "declined" && shareAcceptance) return invalid();
  return { ...readMutation(row), response: row.response, shareAcceptance };
};
const readFeedback = (row: Record<string, unknown>): SchedulingFeedbackInput => ({
  ...readOperation(row), played: requiredBoolean(row.played), bothersome: requiredBoolean(row.bothersome), privacyConcern: requiredBoolean(row.privacyConcern),
});
const readReport = (row: Record<string, unknown>): SchedulingReportInput => {
  if (row.reason !== "spam" && row.reason !== "harassment" && row.reason !== "other") return invalid();
  return { ...readOperation(row), reason: row.reason };
};
const readDevice = (row: Record<string, unknown>): SchedulingDeviceInput => {
  if (typeof row.token !== "string" || !/^[0-9a-f]{64}$/i.test(row.token) ||
    (row.environment !== "sandbox" && row.environment !== "production")) return invalid();
  return { token: row.token.toLowerCase(), environment: row.environment, enabled: requiredBoolean(row.enabled) };
};
