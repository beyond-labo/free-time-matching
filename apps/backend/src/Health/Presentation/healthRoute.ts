import type { Context } from "hono";

export const healthRoute = (context: Context): Response =>
  context.json({ status: "ok" });
