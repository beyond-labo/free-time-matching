import { pathToFileURL } from "node:url";

const DEFAULT_TIMEOUT_MS = 5_000;
const DEFAULT_MAX_ATTEMPTS = 12;
const DEFAULT_RETRY_DELAY_MS = 5_000;

const parsePositiveInteger = (value, name) => {
  const parsed = Number.parseInt(value, 10);

  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }

  return parsed;
};

export const buildHealthUrl = (baseUrl) => {
  const healthUrl = new URL(baseUrl);
  healthUrl.pathname = `${healthUrl.pathname.replace(/\/+$/, "")}/healthz`;
  healthUrl.search = "";
  healthUrl.hash = "";
  return healthUrl;
};

const requestHealth = async ({ healthUrl, timeoutMs, fetchImpl }) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetchImpl(healthUrl, {
      signal: controller.signal,
      headers: { accept: "application/json" },
    });

    if (response.status < 200 || response.status >= 300) {
      return `health endpoint returned HTTP ${response.status}`;
    }

    let payload;

    try {
      payload = await response.json();
    } catch {
      return "health endpoint did not return valid JSON";
    }

    const isExactHealthPayload =
      payload !== null &&
      typeof payload === "object" &&
      !Array.isArray(payload) &&
      Object.keys(payload).length === 1 &&
      payload.status === "ok";

    return isExactHealthPayload
      ? undefined
      : "health endpoint returned an unexpected JSON payload";
  } catch (error) {
    return error?.name === "AbortError"
      ? "health endpoint timed out"
      : "health endpoint could not be reached";
  } finally {
    clearTimeout(timeout);
  }
};

export const runHealthSmoke = async ({
  baseUrl,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  maxAttempts = DEFAULT_MAX_ATTEMPTS,
  retryDelayMs = DEFAULT_RETRY_DELAY_MS,
  fetchImpl = fetch,
  sleep = (delayMs) => new Promise((resolve) => setTimeout(resolve, delayMs)),
  logger = console,
}) => {
  const healthUrl = buildHealthUrl(baseUrl);
  let lastFailure = "health endpoint did not become ready";

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const failure = await requestHealth({ healthUrl, timeoutMs, fetchImpl });

    if (!failure) {
      logger.log(`Backend health smoke passed on attempt ${attempt}/${maxAttempts}`);
      return;
    }

    lastFailure = failure;
    logger.warn(`Backend health smoke attempt ${attempt}/${maxAttempts} failed: ${failure}`);

    if (attempt < maxAttempts) {
      await sleep(retryDelayMs);
    }
  }

  throw new Error(`${lastFailure} after ${maxAttempts} attempts`);
};

const isMain =
  process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isMain) {
  const baseUrl = process.argv[2] ?? process.env.BACKEND_HEALTH_URL;

  try {
    if (!baseUrl) {
      throw new Error("a base URL argument or BACKEND_HEALTH_URL is required");
    }

    await runHealthSmoke({
      baseUrl,
      timeoutMs: parsePositiveInteger(
        process.env.BACKEND_HEALTH_TIMEOUT_MS ?? String(DEFAULT_TIMEOUT_MS),
        "BACKEND_HEALTH_TIMEOUT_MS",
      ),
      maxAttempts: parsePositiveInteger(
        process.env.BACKEND_HEALTH_MAX_ATTEMPTS ?? String(DEFAULT_MAX_ATTEMPTS),
        "BACKEND_HEALTH_MAX_ATTEMPTS",
      ),
      retryDelayMs: parsePositiveInteger(
        process.env.BACKEND_HEALTH_RETRY_DELAY_MS ?? String(DEFAULT_RETRY_DELAY_MS),
        "BACKEND_HEALTH_RETRY_DELAY_MS",
      ),
    });
  } catch (error) {
    console.error(`Backend health smoke failed: ${error.message}`);
    process.exitCode = 1;
  }
}
