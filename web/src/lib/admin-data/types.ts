export type Fields = Record<string, string>;
export type ResourceKind = "comics" | "chapters" | "genres" | "sources" | "accounts" | "helpdesk" | "audit";
export type DemoRecord = {
  id: string; kind: ResourceKind; revision: number; source: Fields; override: Fields;
  archived: boolean; parentId?: string;
};
export type Operation = { id: string; resource: string; status: "pending" | "succeeded" | "failed"; message: string };
export type Workspace = { records: DemoRecord[]; operations: Operation[]; profile: string; revision: number };
export type Mutation = { operationId: string; kind: ResourceKind; id: string; expectedRevision: number; values?: Fields; action: "create" | "update" | "archive" | "restore" | "reset"; resetField?: string };
export type MutationResult = { status: "succeeded" | "conflict" | "invalid" | "pending"; message: string; operationId: string };
export interface AdminDataRepository {
  getSnapshot(): Workspace;
  subscribe(listener: () => void): () => void;
  mutate(change: Mutation, outcome?: string): MutationResult;
  reconcile(operationId: string): MutationResult;
}
export function effective(record: DemoRecord): Fields { return { ...record.source, ...record.override }; }
export const resourceLabels: Record<ResourceKind, string> = { comics: "Komik", chapters: "Chapter", genres: "Genre", sources: "Source", accounts: "Akun", helpdesk: "Helpdesk", audit: "Audit admin" };
export const profiles: Record<string, { label: string; permissions: string[] }> = {
  all: { label: "Semua modul (contoh)", permissions: ["monitoring:read", "logs:read", "data:read", "catalog:write", "users:manage", "users:inspect-library", "helpdesk:manage", "audit:read", "preview:read", "preview:inspect-urls"] },
  viewer: { label: "Viewer monitoring", permissions: ["monitoring:read"] },
  catalog: { label: "Operator katalog", permissions: ["monitoring:read", "data:read", "catalog:write", "preview:read"] },
  helpdesk: { label: "Operator helpdesk", permissions: ["monitoring:read", "helpdesk:manage"] },
  accounts: { label: "Admin akun", permissions: ["users:manage"] },
  auditor: { label: "Auditor", permissions: ["audit:read"] },
};
export const readPermission = (kind: ResourceKind) => kind === "accounts" ? "users:manage" : kind === "helpdesk" ? "helpdesk:manage" : kind === "audit" ? "audit:read" : "data:read";
