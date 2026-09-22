import { Hono } from "hono";
import type { AccessTokenVerifier } from "../../Auth/Application/Port/AccessTokenVerifier";
import { readBearerToken } from "../../Auth/Presentation/BearerToken";
import type { AccountDeletionStatusPort } from "../Application/Port/AccountDeletionPorts";
import type { RequestAccountDeletion } from "../Application/UseCase/RequestAccountDeletion";
import { apiErrorResponse, InvalidRequestError } from "../../Shared/Presentation/ApiError";

export interface AccountDeletionRouteDependencies {
  readonly tokenVerifier: AccessTokenVerifier;
  readonly requestDeletion: Pick<RequestAccountDeletion, "execute">;
  readonly deletionStatus: AccountDeletionStatusPort;
}

export const createAccountDeletionRoutes = (
  dependencies: AccountDeletionRouteDependencies,
) => {
  const routes = new Hono();

  routes.post("/account-deletion-requests", async (context) => {
    try {
      const accessToken = readBearerToken(context.req.header("authorization"));
      const actor = await dependencies.tokenVerifier.verify(accessToken);
      const idempotencyKey = readIdempotencyKey(
        context.req.header("idempotency-key"),
      );
      const appleAuthorizationCode = await readAuthorizationCode(context.req.raw);
      const receipt = await dependencies.requestDeletion.execute({
        userId: actor.id,
        accessToken,
        idempotencyKey,
        appleAuthorizationCode,
      });
      return context.json(receipt);
    } catch (error) {
      return apiErrorResponse(context, error);
    }
  });

  routes.get("/account-deletion-requests/:reference", async (context) => {
    const authorization = context.req.header("authorization");
    const match = authorization?.match(/^Deletion ([^\s]+)$/);
    if (!match) {
      return context.json(
        { error: { code: "unauthorized", message: "削除状況tokenが必要です。" } },
        401,
      );
    }
    try {
      const status = await dependencies.deletionStatus.get(
        context.req.param("reference"),
        match[1],
      );
      if (!status) {
        return context.json(
          { error: { code: "not_found", message: "削除受付が見つかりません。" } },
          404,
        );
      }
      return context.json(status);
    } catch (error) {
      return apiErrorResponse(context, error);
    }
  });

  return routes;
};

const readIdempotencyKey = (value: string | undefined): string => {
  if (!value || value.length < 8 || value.length > 200 || /[^\x21-\x7e]/.test(value)) {
    throw new InvalidRequestError(
      "invalid_idempotency_key",
      "Idempotency-Keyには8〜200文字のASCII文字列を指定してください。",
    );
  }
  return value;
};

const readAuthorizationCode = async (request: Request): Promise<string> => {
  let input: unknown;
  try {
    input = await request.json();
  } catch {
    throw new InvalidRequestError("invalid_json", "JSON形式で入力してください。");
  }
  const code =
    typeof input === "object" && input !== null
      ? (input as Record<string, unknown>).appleAuthorizationCode
      : undefined;
  if (typeof code !== "string" || code.length < 1 || code.length > 4096) {
    throw new InvalidRequestError(
      "invalid_apple_authorization_code",
      "Apple authorization codeを指定してください。",
    );
  }
  return code;
};
