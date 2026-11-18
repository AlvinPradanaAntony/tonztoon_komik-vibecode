"use client";
import { useSyncExternalStore } from "react";
import { createWorkspace } from "@/lib/demo/catalog";
import { effective, profiles, type AdminDataRepository, type Mutation, type MutationResult, type Workspace } from "./types";
const baseline = createWorkspace();
let workspace: Workspace = baseline;
const listeners = new Set<() => void>();
const results = new Map<string, { payload: string; result: MutationResult }>();
const pending = new Map<string, Mutation>();
const emit = () => listeners.forEach(listener => listener());
export const demoRepository: AdminDataRepository = {
  getSnapshot: () => workspace,
  subscribe(listener) { listeners.add(listener); return () => { listeners.delete(listener); }; },
  mutate(change, outcome = "success") {
    const payload = JSON.stringify(change), previous = results.get(change.operationId);
    if (previous) return previous.payload === payload ? previous.result : { status: "conflict", message: "ID tindakan sudah dipakai untuk payload berbeda.", operationId: change.operationId };
    const item = workspace.records.find(record => record.id === change.id && record.kind === change.kind);
    const result = (status: MutationResult["status"], message: string): MutationResult => ({ status, message, operationId: change.operationId });
    const permission = change.kind === "accounts" ? "users:manage" : change.kind === "helpdesk" ? "helpdesk:manage" : "catalog:write";
    if (!profiles[workspace.profile].permissions.includes(permission) || ["sources", "audit"].includes(change.kind)) return result("invalid", "Profil contoh tidak mengizinkan perubahan ini.");
    if (outcome === "conflict" || (item && item.revision !== change.expectedRevision)) return result("conflict", "Konflik versi contoh. Draft dipertahankan; muat versi terbaru sebelum mencoba kembali.");
    if (outcome === "invalid") return result("invalid", "Validasi server disimulasikan ditolak. Periksa draft dan coba kembali.");
    if (outcome === "pending") {
      if(pending.size>=100&&!pending.has(change.operationId))return result('invalid','Batas 100 tindakan contoh tertunda tercapai. Periksa hasil tindakan sebelum membuat yang baru.');
      pending.set(change.operationId, change);
      workspace = { ...workspace, operations: [...workspace.operations.filter(o => o.id !== change.operationId), { id: change.operationId, resource: `${change.kind}:${change.id}`, status: "pending" as const, message: "Hasil contoh belum pasti. Belum dinyatakan tersimpan." }].slice(-100) };
      emit(); return result("pending", "Hasil contoh belum pasti. Periksa status tindakan; draft tetap tersedia.");
    }
    const values = change.values ?? {};
    if (change.action === "create") {
      if(change.kind==='chapters'&&!workspace.records.some(record=>record.kind==='comics'&&record.id===values.comic_id))return result('invalid','Comic ID tidak ada pada data contoh.');
      if(change.kind==='accounts'&&values.role&&values.role!=='reader')return result('invalid','Hanya akun reader nonadmin yang dapat dibuat.');
      const duplicate = workspace.records.some(r => r.kind === change.kind && (change.kind === "comics" ? effective(r).source_name === values.source_name && effective(r).slug === values.slug : change.kind === "chapters" ? effective(r).comic_id === values.comic_id && Number(effective(r).chapter_number) === Number(values.chapter_number) : change.kind === "genres" ? effective(r).slug === values.slug||effective(r).title===values.title : effective(r).title.toLowerCase() === values.title?.toLowerCase()));
      if (duplicate) return result("invalid", "Identitas resource sudah ada pada data contoh.");
      workspace = { ...workspace, records: [...workspace.records, { id: change.id, kind: change.kind, source: values, override: {}, revision: 1, archived: false, parentId: values.comic_id }] };
    } else {
      if (!item) return result("invalid", "Resource contoh tidak ditemukan.");
      const immutable = change.kind === "comics" ? ["source_name", "slug", "rating", "total_views"] : change.kind === "chapters" ? ["comic_id", "chapter_number", "source_url", "total_images", "images_are_invalid"] : change.kind === "genres" ? ["slug"] : ["role", "email_masked"];
      const safe = Object.fromEntries(Object.entries(values).filter(([field]) => !immutable.includes(field)));
      workspace = { ...workspace, records: workspace.records.map(r => {
        if (r !== item) return r;
        const override = { ...r.override, ...safe };
        if (change.action === "reset" && change.resetField) delete override[change.resetField];
        return { ...r, override, revision: r.revision + 1, archived: change.action === "archive" ? true : change.action === "restore" ? false : r.archived };
      }) };
    }
    const auditValues = { title: "Perubahan lokal contoh", actor: "admin-contoh", permission, resource: `${change.kind}:${change.id}`, action: change.action, result: "simulated", operation_id: change.operationId, request_id: "", observed_at: new Date().toISOString(), before: change.kind === "comics" && item ? effective(item).title : "", after: change.kind === "comics" ? values.title ?? "" : "" };
    workspace = { ...workspace, revision: workspace.revision + 1, records: [...workspace.records.filter(record=>record.kind!=='audit'),...workspace.records.filter(record=>record.kind==='audit').slice(-199), { id: `local-${change.operationId}`, kind: "audit" as const, source: auditValues, override: {}, archived: false, revision: 1 }], operations: workspace.operations.map(o => o.id === change.operationId ? { ...o, status: "succeeded" as const, message: "Perubahan lokal dikonfirmasi. Tidak dikirim ke backend." } : o) };
    const done = result("succeeded", "Perubahan contoh disimpan dalam memori sesi ini. Backend tidak diubah.");
    results.set(change.operationId, { payload, result: done });
    if (results.size > 200) results.delete(results.keys().next().value!);
    pending.delete(change.operationId); emit(); return done;
  },
  reconcile(operationId) {
    const change = pending.get(operationId);
    return change ? this.mutate(change) : results.get(operationId)?.result ?? { status: "invalid", operationId, message: "Tindakan tidak ditemukan dalam sesi ini." };
  },
};
export function useWorkspace() { return useSyncExternalStore(demoRepository.subscribe, demoRepository.getSnapshot, () => baseline); }
export function setDemoProfile(profile: string) { if (profiles[profile]) { workspace = { ...workspace, profile }; emit(); } }
export function resetWorkspace() { workspace = createWorkspace(); results.clear(); pending.clear(); emit(); }
