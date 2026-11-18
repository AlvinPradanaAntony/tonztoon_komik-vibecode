import type { ResourceKind } from "./types";
export type DataRoute = { kind: ResourceKind; id?: string; mode: "list" | "detail" | "edit" | "new" | "library"; parentId?: string };
export function parseDataRoute(segments: string[]): DataRoute | null {
  const [kind, id, action, last] = segments;
  if (!["comics", "chapters", "genres", "sources", "accounts", "helpdesk", "audit"].includes(kind)) return null;
  if (kind === "comics" && id && action === "chapters" && segments.length <= 4) return !last || last === "new" ? { kind: "chapters", parentId: id, mode: last ? "new" : "list" } : null;
  if (segments.length > 3) return null;
  if (!id) return { kind: kind as ResourceKind, mode: "list" };
  if (id === "new" && !action) return ["comics", "genres", "accounts"].includes(kind) ? { kind: kind as ResourceKind, mode: "new" } : null;
  if (action && action !== "edit" && !(kind === "accounts" && action === "library")) return null;
  if (action === "edit" && ["sources", "audit"].includes(kind)) return null;
  return { kind: kind as ResourceKind, id, mode: action === "library" ? "library" : action === "edit" ? "edit" : "detail" };
}
export function safeReturn(value: string | null, fallback: string) { return value && /^\/(?:data\/|comic-preview(?:\/|\?)|endpoints(?:\/|\?)|requests(?:\/|\?)|runtime-logs(?:\/|\?)|alerts(?:\/|\?)|overview(?:\?|$))/.test(value) && !value.includes("\\") ? value : fallback; }
