import { createApp } from "../Composition/createApp";
import type { BackendBindings } from "../Composition/createApp";
import { runAutomaticSchedulingTick } from "../AutomaticScheduling/Infrastructure/Adapter/SupabaseSchedulingTickAdapter";
import { dispatchSchedulingNotifications } from "../Notification/Composition/Factory/dispatchSchedulingNotifications";

const apps = new WeakMap<BackendBindings, ReturnType<typeof createApp>>();

/** Keep delivery independent: a failed matching pass must not starve existing notifications. */
export const runScheduledTasks = async (
  bindings: BackendBindings,
  tick: (bindings: BackendBindings) => Promise<void> = runAutomaticSchedulingTick,
  dispatch: (bindings: BackendBindings) => Promise<void> = dispatchSchedulingNotifications,
): Promise<void> => {
  let failed = false;
  try { await tick(bindings); } catch { failed = true; }
  try { await dispatch(bindings); } catch { failed = true; }
  // The underlying response body may contain private data. Do not propagate it
  // into the runtime's automatic scheduled-event exception logging.
  if (failed) throw new Error("Scheduled automatic scheduling failed.");
};

export default {
  fetch(request: Request, env: BackendBindings, executionContext: ExecutionContext) {
    let app = apps.get(env);
    if (!app) { app = createApp(env); apps.set(env, app); }
    return app.fetch(request, env, executionContext);
  },
  scheduled(_controller: ScheduledController, env: BackendBindings, _executionContext: ExecutionContext) {
    return runScheduledTasks(env);
  },
};
