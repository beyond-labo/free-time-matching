import { importPKCS8, SignJWT } from "jose";
import type { NotificationPushPort } from "../../Application/Port/NotificationDeliveryPort";
import type { DeliveryOutcome, NotificationDelivery } from "../../Domain/Model/NotificationDelivery";

export interface ApnsConfiguration {
  readonly teamId: string;
  readonly keyId: string;
  readonly privateKey: string;
  readonly topic: string;
}

export class ApnsNotificationAdapter implements NotificationPushPort {
  private cachedToken?: { value: string; expiresAt: number };
  private signingToken?: Promise<string>;
  constructor(private readonly configuration: ApnsConfiguration) {}

  async send(delivery: NotificationDelivery): Promise<DeliveryOutcome> {
    const host = delivery.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const response = await fetch(`https://${host}/3/device/${delivery.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await this.providerToken()}`,
        "content-type": "application/json",
        "apns-topic": this.configuration.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-id": delivery.id,
        "apns-collapse-id": delivery.id,
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
      },
      body: JSON.stringify({ aps: { alert: { title: "アイマノ", body: message(delivery.kind) }, sound: "default" } }),
      signal: AbortSignal.timeout(10_000),
    });
    if (response.status === 200) return "sent";
    if (response.status === 410) return "invalid_token";
    if (response.status === 400) {
      const body: unknown = await response.json().catch(() => null);
      const reason = typeof body === "object" && body !== null && "reason" in body ? body.reason : undefined;
      if (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic") return "invalid_token";
    }
    return "retry";
  }

  private async providerToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.cachedToken && this.cachedToken.expiresAt > now) return this.cachedToken.value;
    if (this.signingToken) return this.signingToken;
    const signing = (async () => {
      const key = await importPKCS8(this.configuration.privateKey.replace(/\\n/g, "\n"), "ES256");
      const value = await new SignJWT({})
        .setProtectedHeader({ alg: "ES256", kid: this.configuration.keyId })
        .setIssuer(this.configuration.teamId)
        .setIssuedAt(now)
        .sign(key);
      this.cachedToken = { value, expiresAt: now + 50 * 60 };
      return value;
    })();
    this.signingToken = signing;
    try { return await signing; }
    finally { if (this.signingToken === signing) this.signingToken = undefined; }
  }
}

const message = (kind: NotificationDelivery["kind"]): string => {
  switch (kind) {
    case "proposal": return "遊びの候補があります。アプリで確認してください。";
    case "confirmed": return "予定が確定しました。アプリで確認してください。";
    case "cancelled": return "予定が取り消されました。アプリで確認してください。";
  }
};
