import type { NotificationDeliveryRepository } from "../../Application/Port/NotificationDeliveryPort";
import type { DeliveryOutcome, NotificationDelivery } from "../../Domain/Model/NotificationDelivery";
import { supabaseFetch } from "../../../Shared/Infrastructure/SupabaseRestClient";

export class SupabaseNotificationDeliveryRepository implements NotificationDeliveryRepository {
  constructor(private readonly url: string, private readonly secret: string) {}

  async claim(): Promise<readonly NotificationDelivery[]> {
    const response = await this.rpc("automatic_scheduling_delivery_claim", {});
    const value: unknown = await response.json();
    if (!Array.isArray(value) || value.length > 50) throw new Error("invalid_notification_delivery");
    return value.map((row: unknown): NotificationDelivery => {
      if (typeof row !== "object" || row === null || Array.isArray(row)) throw new Error("invalid_notification_delivery");
      const item = row as Record<string, unknown>;
      if (typeof item.id !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(item.id) ||
          typeof item.token !== "string" || !/^[0-9a-f]{64}$/i.test(item.token) ||
          (item.environment !== "sandbox" && item.environment !== "production") ||
          (item.kind !== "proposal" && item.kind !== "confirmed" && item.kind !== "cancelled")) {
        throw new Error("invalid_notification_delivery");
      }
      return { id: item.id, token: item.token, environment: item.environment, kind: item.kind };
    });
  }

  async finish(id: string, outcome: DeliveryOutcome): Promise<void> {
    await this.rpc("automatic_scheduling_delivery_finish", { p_id: id, p_outcome: outcome });
  }

  private rpc(name: string, body: Record<string, unknown>): Promise<Response> {
    return supabaseFetch({ url: this.url, apiKey: this.secret }, `/rest/v1/rpc/${name}`,
      { method: "POST", body: JSON.stringify(body) });
  }
}
