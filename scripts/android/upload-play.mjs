import { createSign } from "node:crypto";
import { readFile } from "node:fs/promises";

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) throw new Error(`Invalid argument: ${key ?? "<missing>"}`);
    result[key.slice(2)] = value;
  }
  return result;
}

function base64url(value) {
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(value);
  return buffer.toString("base64url");
}

async function jsonResponse(response, operation) {
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`${operation} returned non-JSON (${response.status})`);
  }
  if (!response.ok) {
    const message = body?.error?.message ?? body?.error_description ?? response.statusText;
    throw new Error(`${operation} failed (${response.status}): ${message}`);
  }
  return body;
}

async function accessToken(credentials) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: credentials.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: credentials.token_uri,
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const signature = createSign("RSA-SHA256").update(unsigned).end().sign(credentials.private_key);
  const assertion = `${unsigned}.${base64url(signature)}`;
  const response = await fetch(credentials.token_uri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  return (await jsonResponse(response, "OAuth token exchange")).access_token;
}

async function apiJson(url, token, operation, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      ...options.headers,
    },
  });
  return jsonResponse(response, operation);
}

const args = parseArgs(process.argv.slice(2));
for (const name of ["credentials", "package", "bundle", "track", "release-name"]) {
  if (!args[name]) throw new Error(`Missing --${name}`);
}

const credentials = JSON.parse(await readFile(args.credentials, "utf8"));
for (const name of ["client_email", "private_key", "token_uri"]) {
  if (typeof credentials[name] !== "string" || credentials[name].length === 0) {
    throw new Error(`Service account credentials are missing ${name}`);
  }
}
if (credentials.type !== "service_account") {
  throw new Error("Credentials must be a service account key");
}
if (credentials.token_uri !== "https://oauth2.googleapis.com/token") {
  throw new Error("Service account token_uri is not the expected Google OAuth endpoint");
}

const token = await accessToken(credentials);
const packageName = encodeURIComponent(args.package);
const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}`;
const edit = await apiJson(`${base}/edits`, token, "Create edit", { method: "POST", body: "{}" });

try {
  const bundleBytes = await readFile(args.bundle);
  const uploadUrl = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${packageName}/edits/${encodeURIComponent(edit.id)}/bundles?uploadType=media`;
  const uploadResponse = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/octet-stream",
    },
    body: bundleBytes,
  });
  const bundle = await jsonResponse(uploadResponse, "Upload bundle");
  const track = encodeURIComponent(args.track);
  await apiJson(`${base}/edits/${encodeURIComponent(edit.id)}/tracks/${track}`, token, "Update track", {
    method: "PUT",
    body: JSON.stringify({
      track: args.track,
      releases: [{
        name: args["release-name"],
        status: "completed",
        versionCodes: [String(bundle.versionCode)],
      }],
    }),
  });
  await apiJson(`${base}/edits/${encodeURIComponent(edit.id)}:commit`, token, "Commit edit", {
    method: "POST",
    body: "{}",
  });
  console.log(`Uploaded version code ${bundle.versionCode} to ${args.track}.`);
} catch (error) {
  await fetch(`${base}/edits/${encodeURIComponent(edit.id)}`, {
    method: "DELETE",
    headers: { authorization: `Bearer ${token}` },
  }).catch(() => {});
  throw error;
}
