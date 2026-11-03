import { DeliverSchedulingNotifications } from "../../Application/UseCase/DeliverSchedulingNotifications";
import { ApnsNotificationAdapter } from "../../Infrastructure/Adapter/ApnsNotificationAdapter";
import { SupabaseNotificationDeliveryRepository } from "../../Infrastructure/Repository/SupabaseNotificationDeliveryRepository";

export interface NotificationBindings {
  readonly SUPABASE_URL?: string;
  readonly SUPABASE_SECRET_KEY?: string;
  readonly APNS_TEAM_ID?: string;
  readonly APNS_KEY_ID?: string;
  readonly APNS_PRIVATE_KEY?: string;
  readonly APNS_TOPIC?: string;
}

const pushAdapters = new WeakMap<NotificationBindings, ApnsNotificationAdapter>();

export async function dispatchSchedulingNotifications(bindings: NotificationBindings): Promise<void> {
  const { APNS_TEAM_ID: teamId, APNS_KEY_ID: keyId, APNS_PRIVATE_KEY: privateKey, APNS_TOPIC: topic } = bindings;
  if (!teamId && !keyId && !privateKey && !topic) return; // Unleased work survives configuration later.
  if (!teamId || !keyId || !privateKey || !topic || !bindings.SUPABASE_URL || !bindings.SUPABASE_SECRET_KEY) {
    throw new Error("notification_configuration_incomplete");
  }
  let push = pushAdapters.get(bindings);
  if (!push) {
    push = new ApnsNotificationAdapter({ teamId, keyId, privateKey, topic });
    pushAdapters.set(bindings, push);
  }
  await new DeliverSchedulingNotifications(
    new SupabaseNotificationDeliveryRepository(bindings.SUPABASE_URL, bindings.SUPABASE_SECRET_KEY), push,
  ).execute();
}
