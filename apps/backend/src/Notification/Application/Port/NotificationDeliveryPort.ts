import type { DeliveryOutcome, NotificationDelivery } from "../../Domain/Model/NotificationDelivery";

export interface NotificationDeliveryRepository {
  claim(): Promise<readonly NotificationDelivery[]>;
  finish(id: string, outcome: DeliveryOutcome): Promise<void>;
}
export interface NotificationPushPort {
  send(delivery: NotificationDelivery): Promise<DeliveryOutcome>;
}
