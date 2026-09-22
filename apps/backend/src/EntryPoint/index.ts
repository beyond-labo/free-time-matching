import { createApp } from "../Composition/createApp";
import type { BackendBindings } from "../Composition/createApp";

let app: ReturnType<typeof createApp> | undefined;

export default {
  fetch(request: Request, env: BackendBindings, executionContext: ExecutionContext) {
    app ??= createApp(env);
    return app.fetch(request, env, executionContext);
  },
};
