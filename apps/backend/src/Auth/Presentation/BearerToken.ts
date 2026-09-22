import { InvalidAccessTokenError } from "../Application/Port/AccessTokenVerifier";

export const readBearerToken = (authorization: string | undefined): string => {
  const match = authorization?.match(/^Bearer ([^\s]+)$/);
  if (!match) throw new InvalidAccessTokenError();
  return match[1];
};
