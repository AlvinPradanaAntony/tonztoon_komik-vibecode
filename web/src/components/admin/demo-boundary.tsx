"use client";
import type { ReactNode } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Alert, Button, EmptyState, Input, Select, Skeleton } from "@/components/ui";
import { profiles } from "@/lib/admin-data/types";
import { resetWorkspace, setDemoProfile, useWorkspace } from "@/lib/admin-data/demo-repository";
export const viewStates = { normal: "Data contoh", loading: "Memuat", empty: "Tanpa data", error: "Gagal memuat", denied: "Akses ditolak", stale: "Data stale", partial: "Cakupan parsial", timeout: "Timeout", gap: "Gap telemetry", down: "Backend down" };
export function useQueryState() {
  const params = useSearchParams(), pathname = usePathname();
  function set(values: Record<string, string | null>) {
    const next = new URLSearchParams(params);
    for (const [key, value] of Object.entries(values)) { if (value === null || value === "") next.delete(key); else next.set(key, value); }
    window.history.replaceState(null, "", `${pathname}${next.size ? `?${next}` : ""}`);
  }
  function href(path: string, values: Record<string, string | null> = {}) {
    const next = new URLSearchParams(params);
    for (const [key, value] of Object.entries(values)) { if (value === null) next.delete(key); else next.set(key, value); }
    return `${path}${next.size ? `?${next}` : ""}`;
  }
  return { params, pathname, set, href };
}
export function DemoSearch({ label = "Cari", queryKey = "q", maxLength = 200 }: { label?: string; queryKey?: string; maxLength?: number }) {
  const { params, set } = useQueryState();
  const [draft, setDraft] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const apply = (value: string) => { set({ [queryKey]: value, page: null }); setDraft(null); };
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);
  return <Input type="search" label={label} maxLength={maxLength} value={draft ?? params.get(queryKey) ?? ""} onKeyDown={e => { if (e.key === "Enter") { e.preventDefault(); if (timer.current) clearTimeout(timer.current); apply(e.currentTarget.value); } }} onChange={e => { const value = e.target.value; setDraft(value); if (timer.current) clearTimeout(timer.current); timer.current = setTimeout(() => apply(value), 300); }} />;
}
export function DemoBoundary({ permission, children, emptyDescription = "Belum ada resource pada snapshot contoh." }: { permission: string; children: ReactNode; emptyDescription?: string }) {
  const { params, set } = useQueryState(), workspace = useWorkspace();
  const state = params.get("state") ?? "normal";
  const denied = state === "denied" || !profiles[workspace.profile].permissions.includes(permission);
  const blocked = denied || ["loading", "empty", "error", "timeout", "down"].includes(state);
  return <>
    <p className="mb-5 text-xs/5 text-muted">Data contoh lokal dari prototype. Perubahan hanya di memori sesi browser. API, collector, dan izin server belum terhubung.</p>
    {denied ? <Alert tone="error" title="Akses ditolak (contoh)">Profil ini tidak mempunyai izin {permission}. Pilihan profil di bawah hanya simulasi frontend.</Alert> : state === "loading" ? <div aria-busy="true" aria-label="Memuat data contoh" className="space-y-4"><Skeleton className="h-12"/><Skeleton className="h-48"/><Button onClick={() => set({ state: null })}>Selesaikan pemuatan contoh</Button></div> : state === "empty" ? <EmptyState title="Belum ada data" description={emptyDescription} action={<Button onClick={() => set({ state: null })}>Kembali ke data contoh</Button>} /> : ["error", "timeout", "down"].includes(state) ? <Alert tone="error" title={viewStates[state as keyof typeof viewStates]} action={<Button onClick={() => set({ state: null })}>Coba lagi contoh</Button>}>Snapshot tidak dapat dimuat. Status layanan dan koneksi browser tidak disamakan.</Alert> : null}
    {!blocked && <>{["stale", "partial", "gap"].includes(state) && <Alert tone="warning" title={`${viewStates[state as keyof typeof viewStates]} (contoh)`}>Snapshot dipertahankan dengan cakupan terbatas. Tidak dianggap sehat atau pulih. <Button onClick={() => set({ state: null })}>Muat ulang contoh</Button></Alert>}{children}</>}
    <details className="mt-8 rounded-panel bg-panel p-4"><summary className="min-h-11 cursor-pointer text-sm font-medium">Opsi data contoh</summary><div className="mt-4 grid gap-4 sm:grid-cols-2"><Select label="State data" value={state in viewStates ? state : "normal"} onChange={e => set({ state: e.target.value })}>{Object.entries(viewStates).map(([value, label]) => <option value={value} key={value}>{label}</option>)}</Select><Select label="Profil izin contoh" value={workspace.profile} onChange={e => setDemoProfile(e.target.value)}>{Object.entries(profiles).map(([value, profile]) => <option value={value} key={value}>{profile.label}</option>)}</Select><Button onClick={() => { resetWorkspace(); set({ state: null }); }}>Reset data contoh</Button><p className="text-xs/5 text-muted">Simulasi ini tidak memberikan akses atau mengubah izin server. Reload mengembalikan fixture awal.</p></div></details>
  </>;
}
