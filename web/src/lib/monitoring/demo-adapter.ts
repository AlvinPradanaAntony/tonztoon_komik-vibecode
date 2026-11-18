import { endpoints } from "@/lib/demo/monitoring";
import { alertSamples, type Simulation } from "@/lib/demo/overview-simulation";
export function requestSnapshot(sim: Simulation, environment: string, minutes: number) {
  return sim.events.filter(e => e.environment === environment && e.at > sim.now - minutes * 60000 && e.at <= sim.now && e.endpoint < endpoints.length).map(e => ({ ...e, method: "GET", route: endpoints[e.endpoint].route, endpointId: endpoints[e.endpoint].id, group: endpoints[e.endpoint].group, outcome: e.status >= 500 ? "server_error" : "completed", instance: "demo-api-01", observation_id: `obs-${e.id}` })).sort((a, b) => b.at - a.at || a.id.localeCompare(b.id));
}
export type RequestRow = ReturnType<typeof requestSnapshot>[number];
export function sanitizeConsole(value: string) { return value.replace(/\x1b\][\s\S]*?(?:\x07|\x1b\\)/g, "").replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, ""); }
export function runtimeSnapshot(sim: Simulation, environment: string, minutes: number) {
  const requests = requestSnapshot(sim, environment, minutes);
  const startedAt=Date.UTC(2026,9,28,6,4,39);
  const lifecycle = environment === "production" && startedAt>sim.now-minutes*60000&&startedAt<=sim.now ? [{ id: "demo-startup", at: startedAt, received_at: startedAt+20, level: "INFO", kind: "lifecycle", logger: "uvicorn.error", message: "Application startup complete.", request_id: "", instance: "demo-api-01", capture_kind: "structured_render", exception: "", frames: [] as string[] }] : [];
  return [...lifecycle, ...requests.map(r => ({ id: r.id, at: r.at, received_at: r.at + 20, level: r.status >= 500 ? "ERROR" : r.status >= 400 ? "WARNING" : "INFO", kind: r.status >= 500 ? "application" : "access", logger: r.status >= 500 ? "app.reader" : "uvicorn.access", message: sanitizeConsole(`${r.method} ${r.route} ${r.status} ${r.duration}ms`), request_id: r.id, instance: r.instance, capture_kind: "structured_render", exception: r.status >= 500 ? "UpstreamTimeout" : "", frames: r.status >= 500 ? ["reader.py:82 in fetch_chapter", "transport.py:41 in read_response", "UpstreamTimeout: response exceeded deadline"] : [] }))].sort((a, b) => a.received_at - b.received_at || a.id.localeCompare(b.id)).slice(-1000);
}
export type RuntimeEvent = ReturnType<typeof runtimeSnapshot>[number];
export function consoleText(event: RuntimeEvent) { return sanitizeConsole(`${new Date(event.at).toISOString()} ${event.level} ${event.logger} ${event.message}${event.frames.length ? `\nTraceback (sanitized):\n  ${event.frames.join("\n  ")}` : ""}`); }
export function evaluateAlerts(sim: Simulation, environment: string) {
  return alertSamples(sim,environment).map(sample=>{const incident=sim.incidents?.find(incident=>incident.id===sample.id&&incident.environment===environment),timeline=incident?.timeline.filter(transition=>transition.at<=sim.now);return {...sample,state:!sample.known?'unknown':timeline?.at(-1)?.state??(sample.bad?'pending':'resolved'),at:sim.now,timeline:timeline?.length?timeline:[{at:sim.now,state:!sample.known?'unknown':sample.bad?'pending':'resolved'}]};});
}
