import type { NotificationDeliveryRepository, NotificationPushPort } from "../Port/NotificationDeliveryPort";

export class DeliverSchedulingNotifications {
  constructor(
    private readonly repository: NotificationDeliveryRepository,
    private readonly push: NotificationPushPort,
  ) {}

  async execute(): Promise<void> {
    const deliveries = await this.repository.claim();
    const results = await Promise.allSettled(deliveries.map(async (delivery) => {
      const outcome = await this.push.send(delivery).catch(() => "retry" as const);
      // A failed acknowledgement leaves a recoverable lease. Retries keep the
      // same delivery ID, which is also used as the APNs collapse ID.
      await this.repository.finish(delivery.id, outcome);
      if (outcome === "retry") throw new Error("notification_delivery_pending");
    }));
    if (results.some((result) => result.status === "rejected")) {
      throw new Error("notification_delivery_pending");
    }
  }
}
