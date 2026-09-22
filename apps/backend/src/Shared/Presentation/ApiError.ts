import type { Context } from "hono";
import { InvalidAccessTokenError } from "../../Auth/Application/Port/AccessTokenVerifier";
import { AppleReauthenticationError } from "../../AccountDeletion/Application/Port/AccountDeletionPorts";
import { InvalidProfileError } from "../../User/Domain/Model/UserProfile";
import { AccountDeletionInProgressError } from "../../User/Application/Port/ProfileRepository";

export class InvalidRequestError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly fields?: Readonly<Record<string, string>>,
  ) {
    super(message);
    this.name = "InvalidRequestError";
  }
}

export const apiErrorResponse = (context: Context, error: unknown): Response => {
  if (error instanceof InvalidAccessTokenError) {
    return context.json(
      { error: { code: "unauthorized", message: "認証が必要です。" } },
      401,
    );
  }
  if (error instanceof AppleReauthenticationError) {
    return context.json(
      {
        error: {
          code: "apple_reauthentication_failed",
          message: "Appleで再認証してください。",
        },
      },
      401,
    );
  }
  if (error instanceof AccountDeletionInProgressError) {
    return context.json(
      {
        error: {
          code: "account_deletion_in_progress",
          message: "アカウント削除の処理中です。",
        },
      },
      403,
    );
  }
  if (error instanceof InvalidProfileError) {
    return context.json(
      {
        error: {
          code: "invalid_profile",
          message: "プロフィールを確認してください。",
          fields: error.fields,
        },
      },
      400,
    );
  }
  if (error instanceof InvalidRequestError) {
    return context.json(
      {
        error: {
          code: error.code,
          message: error.message,
          ...(error.fields ? { fields: error.fields } : {}),
        },
      },
      400,
    );
  }

  return context.json(
    {
      error: {
        code: "service_unavailable",
        message: "一時的に処理できません。時間をおいて再試行してください。",
      },
    },
    503,
  );
};
