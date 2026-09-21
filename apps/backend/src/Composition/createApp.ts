import { Hono } from "hono";
import { healthRoute } from "../Health/Presentation/healthRoute";

export const createApp = () => {
  const app = new Hono();

  app.get("/healthz", healthRoute);
  app.notFound(() => new Response(null, { status: 404 }));

  return app;
};
