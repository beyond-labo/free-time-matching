export type NotificationKind = "proposal" | "confirmed" | "cancelled";
export interface NotificationDelivery {
  readonly id: string;
  readonly token: string;
  readonly environment: "sandbox" | "production";
  readonly kind: NotificationKind;
}
export type DeliveryOutcome = "sent" | "retry" | "invalid_token";
