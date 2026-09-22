import type { StatusTokenIssuer } from "../../Application/Port/AccountDeletionPorts";

const encoder = new TextEncoder();

const base64Url = (bytes: Uint8Array): string => {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
};

const hex = (bytes: Uint8Array): string =>
  Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

export class HmacStatusTokenIssuer implements StatusTokenIssuer {
  constructor(private readonly secret: string) {
    if (secret.length < 32) {
      throw new Error("ACCOUNT_DELETION_STATUS_SECRET must contain at least 32 characters.");
    }
  }

  async issue(reference: string): Promise<string> {
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(this.secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(reference));
    return base64Url(new Uint8Array(signature));
  }

  async hash(token: string): Promise<string> {
    return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(token))));
  }
}
