import { Hono } from "hono";
import type { AccessTokenVerifier } from "../../Auth/Application/Port/AccessTokenVerifier";
import { readBearerToken } from "../../Auth/Presentation/BearerToken";
import type { ManageProfile } from "../Application/UseCase/ManageProfile";
import type { ProfileInput } from "../Domain/Model/UserProfile";
import { apiErrorResponse, InvalidRequestError } from "../../Shared/Presentation/ApiError";

export interface UserRouteDependencies {
  readonly tokenVerifier: AccessTokenVerifier;
  readonly manageProfile: Pick<ManageProfile, "get" | "put">;
}

export const createUserRoutes = (dependencies: UserRouteDependencies) => {
  const routes = new Hono();

  routes.get("/me", async (context) => {
    try {
      const accessToken = readBearerToken(context.req.header("authorization"));
      const actor = await dependencies.tokenVerifier.verify(accessToken);
      const profile = await dependencies.manageProfile.get(actor.id, accessToken);
      return context.json({
        userId: actor.id,
        profile: profile ? projectProfile(profile) : null,
      });
    } catch (error) {
      return apiErrorResponse(context, error);
    }
  });

  routes.put("/me", async (context) => {
    try {
      const accessToken = readBearerToken(context.req.header("authorization"));
      const actor = await dependencies.tokenVerifier.verify(accessToken);
      const input = await readProfileInput(context.req.raw);
      const profile = await dependencies.manageProfile.put(actor.id, accessToken, input);
      return context.json({ userId: actor.id, profile: projectProfile(profile) });
    } catch (error) {
      return apiErrorResponse(context, error);
    }
  });

  return routes;
};

const projectProfile = (profile: {
  nickname: string;
  presetIconKey: string;
}) => ({
  nickname: profile.nickname,
  presetIconKey: profile.presetIconKey,
});

const readProfileInput = async (request: Request): Promise<ProfileInput> => {
  let input: unknown;
  try {
    input = await request.json();
  } catch {
    throw new InvalidRequestError("invalid_json", "JSON形式で入力してください。");
  }
  if (
    typeof input !== "object" ||
    input === null ||
    typeof (input as Record<string, unknown>).nickname !== "string" ||
    typeof (input as Record<string, unknown>).presetIconKey !== "string"
  ) {
    throw new InvalidRequestError(
      "invalid_profile",
      "nicknameとpresetIconKeyを指定してください。",
    );
  }
  return {
    nickname: (input as Record<string, string>).nickname,
    presetIconKey: (input as Record<string, string>).presetIconKey,
  };
};
