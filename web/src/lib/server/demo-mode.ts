import "server-only";
export function isFrontendDemoEnabled() { return process.env.ADMIN_FRONTEND_DEMO === "true"; }
