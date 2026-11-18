"use client";
import dynamic from "next/dynamic";
import {useSyncExternalStore} from 'react';
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { Alert, Button, Panel, Select, Table } from "@/components/ui";
import { schemaRelations, schemaTables, diagramLabels } from "@/lib/diagrams/manifest";
import { profiles } from "@/lib/admin-data/types";
import { useWorkspace } from "@/lib/admin-data/demo-repository";
import { DemoBoundary, DemoSearch, useQueryState } from "@/components/admin/demo-boundary";
import { PageTitle } from "@/components/admin/patterns";
import { textLink } from "@/components/ui/styles";
const Canvas = dynamic(() => import("./schema-canvas"), { ssr: false, loading: () => <p className="p-5" role="status">Memuat viewer ERD…</p> });
const subscribeDesktop=(listener:()=>void)=>{const media=matchMedia('(min-width:1024px)');media.addEventListener('change',listener);return()=>media.removeEventListener('change',listener);};
export function ErdExplorer() {
  const { params, set, href } = useQueryState(), workspace = useWorkspace();
  const desktop=useSyncExternalStore(subscribeDesktop,()=>matchMedia('(min-width:1024px)').matches,()=>false);
  const diagram = (params.get("diagram") ?? "") in diagramLabels ? params.get("diagram")! : "catalog";
  const q = (params.get("q") ?? "").toLowerCase(), planned = params.get("schema") === "planned";
  const tables = schemaTables.filter(table => table.diagram === diagram && (planned || table.status === "existing"));
  const relations = schemaRelations.filter(relation => tables.some(table => table.id === relation.source) && tables.some(table => table.id === relation.target)||relation.kind==='Relasi logis'&&tables.some(table=>table.id===relation.source||table.id===relation.target));
  const canvasRelations=relations.filter(relation=>tables.some(table=>table.id===relation.source)&&tables.some(table=>table.id===relation.target));
  const selected = tables.find(table => table.id === params.get("table")), relation = relations.find(relation => relation.id === params.get("edge"));
  const filtered = tables.filter(table => !q || `${table.name} ${table.columns.map(column => `${column.name} ${column.type}`).join(" ")}`.toLowerCase().includes(q));
  const view = params.get("view") ?? "auto";
  function closeInspector() {
    const id = selected?.id, label = relation?.label;
    set({ table: null, edge: null });
    requestAnimationFrame(() => {
      const targets = id ? document.querySelectorAll<HTMLElement>(`[data-erd-select="${CSS.escape(id)}"],.react-flow__node[data-id="${CSS.escape(id)}"]`) : document.querySelectorAll<HTMLElement>('button');
      const target = Array.from(targets).find(element => element.getClientRects().length && (id || element.textContent?.trim() === label));
      (target ?? document.querySelector<HTMLElement>('.tt-erd'))?.focus();
    });
  }
  return <><PageTitle title="ERD explorer" description="Empat diagram baca saja dan data dictionary. Tidak menampilkan row data pribadi."/><DemoBoundary permission="data:read"><Panel title="Model data TonzToon" description="Legend: FK terdefinisi · Relasi logis · Usulan migration. Tampilan existing menjadi awal."><div className="mb-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><Select label="Diagram" value={diagram} onChange={event => set({ diagram: event.target.value, table: null, edge: null, q: null, schema: ["monitoring", "admin"].includes(event.target.value) ? "planned" : "existing" })}>{Object.entries(diagramLabels).map(([value, label]) => <option value={value} key={value}>{label}</option>)}</Select><Select label="Cakupan schema" value={planned ? "planned" : "existing"} onChange={event => set({ schema: event.target.value, table: null, edge: null })}><option value="existing">Existing (subset model)</option><option value="planned">Existing + rancangan PRD</option></Select><DemoSearch label="Cari tabel / kolom"/><Select label="Tampilan ERD" value={view} onChange={event => set({ view: event.target.value })}><option value="auto">Adaptif (daftar pada mobile)</option><option value="canvas">Diagram</option><option value="list">Daftar</option></Select></div>
      {planned && <Alert tone="warning" title="Rancangan PRD, penerapan DB belum diverifikasi">Source backend sudah memuat tabel monitoring/admin dengan beberapa nama dan struktur berbeda. Diagram C/D mempertahankan rancangan PRD berlabel usulan; audit kontrak dan rekonsiliasi migration dilakukan pada fase 3.</Alert>}
      <div className={view === "list" ? "hidden" : view === "auto" ? "hidden lg:block" : "block"}>{view!=='list'&&(view==='canvas'||desktop)?<Canvas key={`${diagram}:${planned}`} tables={tables} relations={canvasRelations} selected={selected?.id} selectedEdge={relation?.id} query={q} onSelect={table => set({ table, edge: null })} onSelectEdge={edge => set({ edge, table: null })} onClear={closeInspector}/>:<p className="p-5" role="status">Memuat viewer ERD…</p>}</div>
      <div className={view === "canvas" ? "hidden" : view === "auto" ? "lg:hidden" : ""}><Table caption="Tabel dan kolom, alternatif diagram" data={filtered} columns={[{ accessorKey: "name", header: "Tabel", cell: ({ row }) => <Button data-erd-select={row.original.id} variant="ghost" onClick={() => set({ table: row.original.id, edge: null })}>{row.original.name}</Button> }, { accessorKey: "status", header: "Status" }, { id: "columns", header: "Kolom", cell: ({ row }) => row.original.columns.map(column => `${column.name} (${column.type})`).join(", ") }]} pagination={false}/></div>
      {q && <div className="my-4 flex flex-wrap gap-2">{filtered.map(table => <Button key={table.id} onClick={() => set({ table: table.id, edge: null })}>Pilih {table.name}</Button>)}{!filtered.length && <p role="status">Tidak ada tabel / kolom yang cocok.</p>}</div>}
      <details className="mt-4"><summary className="min-h-11 cursor-pointer py-3">Relasi dan constraint</summary><Table caption="Relasi schema" data={relations} columns={[{ accessorKey: "label", header: "Relasi", cell: ({ row }) => <Button variant="ghost" onClick={() => set({ edge: row.original.id, table: null })}>{row.original.label}</Button> }, { accessorKey: "kind", header: "Jenis" }]} pagination={false}/></details>
    </Panel>{selected && <Panel title={`Data dictionary · ${selected.name}`} description={`${selected.status} · ${selected.source}`} onKeyDown={event=>{if(event.key==='Escape')closeInspector();}} actions={<Button onClick={closeInspector}>Tutup inspector</Button>}><Table caption="Kolom, tipe, nullability dan key" data={selected.columns} columns={[{ accessorKey: "name", header: "Kolom", meta: { rowHeader: true } }, { accessorKey: "type", header: "Tipe" }, { accessorKey: "constraints", header: "Constraint" }, { accessorKey: "nullable", header: "Nullable" }]} pagination={false}/><ul className="my-4 list-inside list-disc text-sm">{selected.constraints.map(constraint => <li key={constraint}>{constraint}</li>)}</ul><p className="mb-4 text-sm text-muted">Manifest subset PRD/model. Tidak melakukan introspeksi database browser. Nilai nullable yang belum diperiksa diberi label eksplisit.</p>{selected.href && selected.permission && profiles[workspace.profile].permissions.includes(selected.permission) && <Link className={textLink} href={href(selected.href)}>Lihat data berizin</Link>}</Panel>}{relation && <Panel title="Inspector relasi" onKeyDown={event=>{if(event.key==='Escape')closeInspector();}} actions={<Button onClick={closeInspector}>Tutup inspector</Button>}><p>{relation.label}</p><p className="mt-3 text-sm text-muted">{relation.kind}. Relasi logis tidak dinyatakan sebagai FK yang terpasang.</p></Panel>}</DemoBoundary></>;
}
