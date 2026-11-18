"use client";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { Badge, Button, Panel, Select, Table } from "@/components/ui";
import { flowEdges, flowNodes } from "@/lib/diagrams/manifest";
import { DemoBoundary, DemoSearch, useQueryState } from "@/components/admin/demo-boundary";
import { PageTitle } from "@/components/admin/patterns";
import { textLink } from "@/components/ui/styles";
import { cx } from "@/components/ui/types";
import "@/styles/data-flow.css";
const subscribeVisibility = (listener: () => void) => { document.addEventListener("visibilitychange", listener); return () => document.removeEventListener("visibilitychange", listener); };
export function DataFlowViewer() {
  const { params, set, href } = useQueryState(), stage = useRef<HTMLDivElement>(null), drag = useRef<{ x: number; y: number; startX: number; startY: number } | null>(null);
  const [viewport, setViewport] = useState({ x: 24, y: 24, scale: .6 }), [heights, setHeights] = useState<Record<string, number>>({}), [playing, setPlaying] = useState(false);
  const visible = useSyncExternalStore(subscribeVisibility, () => !document.hidden, () => true);
  const selectedId = params.get("node"), edgeId = params.get("edge"), view = params.get("view") ?? "auto", mode = params.get("flowMode") ?? "architecture", dataState=params.get('state');
  const q = (params.get("q") ?? "").toLowerCase(), domain = params.get("domain");
  const nodes = flowNodes.filter(node => (!domain || node.domain === domain) && (mode !== "mutation" || node.domain === "admin" || node.id === "api" || node.id === "db"));
  const edges = flowEdges.filter(edge => nodes.some(n => n.id === edge.source) && nodes.some(n => n.id === edge.target));
  const selected = flowNodes.find(node => node.id === selectedId), edge = flowEdges.find(edge => edge.id === edgeId);
  const animated = playing && visible && mode === "demo" && !["stale", "gap", "partial"].includes(params.get("state") ?? "");
  function fit() {
    if (!stage.current || !nodes.length) return;
    const width = Math.max(...nodes.map(n => n.x + 240)) + 24, height = Math.max(...nodes.map(n => n.y + (heights[n.id] ?? 160))) + 24;
    const scale = Math.min(1.2, (stage.current.clientWidth - 32) / width, (stage.current.clientHeight - 32) / height);
    setViewport({ x: (stage.current.clientWidth - width * scale) / 2, y: (stage.current.clientHeight - height * scale) / 2, scale: Math.max(.15, scale) });
  }
  function zoom(factor: number) { setViewport(v => { const scale = Math.min(2, Math.max(.15, v.scale * factor)), x = (stage.current?.clientWidth ?? 800) / 2, y = (stage.current?.clientHeight ?? 600) / 2; return { x: x - (x - v.x) * scale / v.scale, y: y - (y - v.y) * scale / v.scale, scale }; }); }
  function focusNode(id: string) { if (stage.current) { const node = flowNodes.find(n => n.id === id)!; setViewport(v => ({ ...v, x: stage.current!.clientWidth / 2 - (node.x + 120) * v.scale, y: stage.current!.clientHeight / 2 - (node.y + 80) * v.scale })); } }
  function selectNode(id: string, focus = false) { set({ node: id, edge: null }); if (focus) focusNode(id); }
  function closeInspector() {
    const id = selectedId ?? edgeId, label = selected?.label ?? edge?.label;
    set({ node: null, edge: null });
    requestAnimationFrame(() => {
      const targets = id ? document.querySelectorAll<HTMLElement>(`[data-flow-node="${CSS.escape(id)}"],button`) : [];
      const target = Array.from(targets).find(element => element.getClientRects().length && (element.dataset.flowNode === id || element.textContent?.trim() === label));
      (target ?? stage.current)?.focus();
    });
  }
  useEffect(() => {
    const observer = new ResizeObserver(entries => setHeights(previous => { const next = { ...previous }; let changed = false; for (const entry of entries) { const id = (entry.target as HTMLElement).dataset.flowNode!; if (next[id] !== entry.borderBoxSize[0].blockSize) { next[id] = entry.borderBoxSize[0].blockSize; changed = true; } } return changed ? next : previous; }));
    document.querySelectorAll("[data-flow-node]").forEach(node => observer.observe(node)); return () => observer.disconnect();
  }, [domain, mode, dataState]);
  return <><PageTitle title="Data flow" description="Peta komponen TonzToon. Arah arsitektur dipisahkan dari aktivitas terukur."/><DemoBoundary permission="monitoring:read"><Panel title="Alur data" description="Registry contoh dari PRD/source. Tidak ada trace per-hop atau telemetry edge terhubung.">
    <div className="mb-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><DemoSearch label="Cari node"/><Select label="Domain / layer" value={domain ?? ""} onChange={e => set({ domain: e.target.value, node: null, edge: null })}><option value="">Semua domain</option><option value="business">Bisnis</option><option value="admin">Admin / mutation</option><option value="telemetry">Telemetry</option></Select><Select label="Mode alur" value={mode} onChange={e => { set({ flowMode: e.target.value }); setPlaying(false); }}><option value="architecture">Arsitektur</option><option value="activity">Aktivitas terukur (belum tersedia)</option><option value="mutation">Alur perubahan admin</option><option value="demo">Demonstrasi arah (contoh)</option></Select><Select label="Tampilan flow" value={view} onChange={e => set({ view: e.target.value })}><option value="auto">Adaptif (daftar pada mobile)</option><option value="canvas">Diagram</option><option value="list">Daftar</option></Select></div>
    <div className="mb-4 flex flex-wrap gap-2"><Button onClick={() => zoom(1.2)}>Perbesar</Button><Button onClick={() => zoom(1 / 1.2)}>Perkecil</Button><Button onClick={fit}>Fit view</Button><Button onClick={() => setViewport({ x: 24, y: 24, scale: .6 })}>Reset viewport</Button><Button disabled={mode !== "demo"} onClick={() => setPlaying(!playing)}>{playing ? "Jeda demonstrasi" : "Putar demonstrasi arah"}</Button><span className="self-center text-sm text-muted">Zoom {Math.round(viewport.scale * 100)}% · {mode === "demo" ? "Demonstrasi, bukan trafik nyata" : "Edge belum diukur"}</span></div>
    {q && <div className="mb-4 flex flex-wrap gap-2">{nodes.filter(node => `${node.id} ${node.label}`.toLowerCase().includes(q)).map(node => <Button key={node.id} onClick={() => selectNode(node.id, true)}>Pilih {node.label}</Button>)}{!nodes.some(node => `${node.id} ${node.label}`.toLowerCase().includes(q)) && <p role="status">Tidak ada node yang cocok.</p>}</div>}
    <div ref={stage} tabIndex={0} role="region" aria-label="Canvas Data Flow. Tombol pan dan zoom tersedia; pan juga dapat dilakukan dengan tombol panah." className={cx("relative h-144 overflow-hidden rounded-control border border-control bg-canvas touch-none", view === "list" ? "hidden" : view === "auto" ? "hidden lg:block" : "block")} onKeyDown={e => { if(e.key==='Escape'){e.preventDefault();closeInspector();return;} if (e.target !== e.currentTarget) return; const delta: Record<string, [number, number]> = { ArrowLeft: [40, 0], ArrowRight: [-40, 0], ArrowUp: [0, 40], ArrowDown: [0, -40] }; if (delta[e.key]) { e.preventDefault(); setViewport(v => ({ ...v, x: v.x + delta[e.key][0], y: v.y + delta[e.key][1] })); } }} onPointerDown={e => { if ((e.target as Element).closest("button,a,[role=button]")) return; e.currentTarget.setPointerCapture(e.pointerId); drag.current = { x: e.clientX, y: e.clientY, startX: viewport.x, startY: viewport.y }; }} onPointerMove={e => { if (drag.current) setViewport(v => ({ ...v, x: drag.current!.startX + e.clientX - drag.current!.x, y: drag.current!.startY + e.clientY - drag.current!.y })); }} onPointerUp={() => { drag.current = null; }} onPointerCancel={() => { drag.current = null; }}>
      <div className="absolute inset-0 origin-top-left" style={{ transform: `translate(${viewport.x}px,${viewport.y}px) scale(${viewport.scale})` }}>
        <svg width="1540" height="760" className="pointer-events-none absolute inset-0 overflow-visible" aria-label="Relasi arsitektur">
          <defs><marker id="tt-flow-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" className="fill-control"/></marker></defs>
          {edges.map(e => {
            const from = nodes.find(n => n.id === e.source)!, to = nodes.find(n => n.id === e.target)!;
            const forward = to.x >= from.x, x1 = from.x + (forward ? 240 : 0), x2 = to.x + (forward ? 0 : 240), y1 = from.y + (heights[from.id] ?? 160) / 2, y2 = to.y + (heights[to.id] ?? 160) / 2, middle = (x1 + x2) / 2;
            return <g key={e.id}><path role="button" tabIndex={0} aria-label={`${e.label}, belum diukur`} onClick={() => set({ edge: e.id, node: null })} onKeyDown={event => { if (["Enter", " "].includes(event.key)) { event.preventDefault(); set({ edge: e.id, node: null }); } }} d={`M${x1},${y1} C${middle},${y1} ${middle},${y2} ${x2},${y2}`} fill="none" markerEnd="url(#tt-flow-arrow)" strokeWidth={edgeId === e.id ? 4 : 2.5} className={cx("pointer-events-auto cursor-pointer stroke-control [stroke-dasharray:8_5]", edgeId === e.id && "stroke-accent", animated && "motion-safe:animate-[tt-flow-dash_1.2s_linear_infinite]")}><title>{`${e.label} · Belum diukur`}</title></path></g>;
          })}
        </svg>
      {nodes.map(node => <button key={node.id} data-flow-node={node.id} className={cx("card absolute w-60 cursor-pointer rounded-panel border-2 border-line bg-surface p-4 text-start text-foreground", (selectedId === node.id || q && `${node.id} ${node.label}`.toLowerCase().includes(q)) && "border-accent")} style={{ left: node.x, top: node.y }} onClick={() => selectNode(node.id)} onFocus={() => focusNode(node.id)}><strong className="mb-2 block text-base">{node.label}</strong><span className="block text-xs/5 text-muted">{node.description}</span><Badge className="mt-3 whitespace-normal">{node.status}</Badge></button>)}</div>
    </div>
    <div className={cx("mt-4", view === "canvas" ? "hidden" : view === "auto" ? "lg:hidden" : "")}><Table caption="Alternative daftar node flow" data={nodes.filter(n => !q || `${n.id} ${n.label}`.toLowerCase().includes(q))} columns={[{ accessorKey: "label", header: "Komponen", cell: ({ row }) => <Button variant="ghost" onClick={() => selectNode(row.original.id)}>{row.original.label}</Button> }, { accessorKey: "domain", header: "Domain" }, { accessorKey: "status", header: "Cakupan" }]} pagination={false}/></div>
    <details className="mt-5"><summary className="min-h-11 cursor-pointer py-3">Daftar relasi dan arah</summary><Table caption="Relasi flow, belum diukur" data={edges} columns={[{ accessorKey: "label", header: "Relasi", cell: ({ row }) => <Button variant="ghost" onClick={() => set({ edge: row.original.id, node: null })}>{row.original.label}</Button> }, { accessorKey: "source", header: "Dari" }, { accessorKey: "target", header: "Ke" }]} pagination={false}/></details>
  </Panel>{(selected || edge) && <Panel title={`Inspector ${selected?.label ?? edge?.label}`} onKeyDown={event=>{if(event.key==='Escape'){event.preventDefault();closeInspector();}}} actions={<Button onClick={closeInspector}>Tutup inspector</Button>}><p className="mb-3 text-sm">{selected?.description ?? `${edge?.source} → ${edge?.target}`}</p><p className="mb-3 text-sm text-muted">Asal: registry contoh PRD/source · observed_at: belum tersedia · RPS/p95/5xx: belum diukur. Status ini bukan health live.</p>{selected?.href && <Link className={textLink} href={href(selected.href)}>Buka modul terkait</Link>}{edge?.target === "api" && <Link className={textLink} href={href("/endpoints")}>Periksa endpoint terkait</Link>}</Panel>}</DemoBoundary></>;
}
