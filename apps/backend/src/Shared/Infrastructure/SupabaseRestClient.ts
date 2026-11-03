export class SupabaseRequestError extends Error {
  constructor(
    readonly status: number,
    readonly responseBody: string,
  ) {
    super(`Supabase request failed with status ${status}.`);
    this.name = "SupabaseRequestError";
  }
}

export interface SupabaseRestConfiguration {
  readonly url: string;
  readonly apiKey: string;
}

export const supabaseFetch = async (
  configuration: SupabaseRestConfiguration,
  path: string,
  init: RequestInit,
  accessToken?: string,
): Promise<Response> => {
  const headers = new Headers(init.headers);
  headers.set("apikey", configuration.apiKey);
  if (accessToken !== undefined) {
    headers.set("authorization", `Bearer ${accessToken}`);
  } else if (configuration.apiKey.startsWith("sb_")) {
    // Publishable/secret API keys are not JWTs. The gateway resolves their
    // database role from apikey; only a user's access JWT belongs in Bearer.
    headers.delete("authorization");
  } else {
    // Preserve the legacy anon/service_role JWT transport during migration.
    headers.set("authorization", `Bearer ${configuration.apiKey}`);
  }
  if (init.body !== undefined && !headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }

  const response = await fetch(`${configuration.url.replace(/\/$/, "")}${path}`, {
    ...init,
    headers,
  });
  if (!response.ok) {
    throw new SupabaseRequestError(response.status, await response.text());
  }
  return response;
};
