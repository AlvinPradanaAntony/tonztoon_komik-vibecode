"use client";
import { useEffect, useRef, useState } from "react";
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { Alert, Badge, Button, Checkbox, Panel, Select, Tabs } from "@/components/ui";
import type { Simulation } from "@/lib/demo/overview-simulation";
import { consoleText, runtimeSnapshot, type RuntimeEvent } from "@/lib/monitoring/demo-adapter";
import { DemoSearch, useQueryState } from "./demo-boundary";
import { UrlTable } from "./url-table";
import { textLink } from "@/components/ui/styles";
import { detailList } from "./patterns";
import { cx } from "@/components/ui/types";
export function RuntimeViewer({ simulation, environment, minutes, id }: { simulation: Simulation; environment: string; minutes: number; id?: string }) {
  const { params, set, href } = useQueryState();
  const [frozen, setFrozen] = useState<Simulation | null>(null), [auto, setAuto] = useState(false), [wrap, setWrap] = useState(true), [expanded, setExpanded] = useState(false), [cleared, setCleared] = useState(0), [notice, setNotice] = useState("");
  const output = useRef<HTMLDivElement>(null), positions = useRef<Record<string, number>>({});
  const mode = params.get("mode") === "structured" ? "structured" : "terminal";
  const live = runtimeSnapshot(simulation, environment, minutes), events = runtimeSnapshot(frozen ?? simulation, environment, minutes);
  const q = (params.get("q") ?? "").toLowerCase();
  const filtered = events.filter(event => event.at > cleared && (!params.get("level") || event.level === params.get("level")) && (!params.get("logger") || event.logger === params.get("logger")) && (!params.get("kind") || event.kind === params.get("kind")) && (!params.get("instance") || event.instance === params.get("instance")) && (!params.get("request_id") || event.request_id === params.get("request_id")) && (!q || event.message.toLowerCase().includes(q)));
  const selected = events.find(event => event.id === (id ?? params.get("event")));
  const waiting = frozen ? live.filter(event => !events.some(old => old.id === event.id)).length : 0;
  useEffect(() => {
    if (output.current && auto && !frozen && !window.getSelection()?.toString()) output.current.scrollTop = output.current.scrollHeight;
  }, [simulation, auto, frozen, filtered.length]);
  useEffect(() => { if (output.current) output.current.scrollTop = positions.current[mode] ?? 0; }, [mode]);
  const filter = (key: string, label: string, options: string[]) => <Select label={label} value={params.get(key) ?? ""} onChange={e => set({ [key]: e.target.value, page: null })}><option value="">Semua {label.toLowerCase()}</option>{options.map(value => <option key={value}>{value}</option>)}</Select>;
  const copy = async (text: string) => { try { await navigator.clipboard.writeText(text); setNotice("Teks tersanitasi disalin."); } catch { setNotice("Clipboard tidak tersedia. Pilih teks untuk menyalin."); } };
  const pick = (event: RuntimeEvent) => set({ event: event.id });
  return <>
    <Panel title="Output FastAPI / Uvicorn" description="Console dibentuk dari record contoh, bukan tangkapan proses asli. Viewer baca saja.">
      <div className="mb-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><DemoSearch label="Cari pesan runtime"/>{filter("level", "Level", ["INFO", "WARNING", "ERROR"])}{filter("logger", "Logger", ["uvicorn.error", "uvicorn.access", "app.reader"])}{filter("kind", "Jenis", ["lifecycle", "access", "application", "pipeline"])}{filter("instance", "Instance", ["demo-api-01"])}<DemoSearch label="Request ID persis" queryKey="request_id"/><Button onClick={() => set({ q: null, level: null, logger: null, kind: null, instance: null, request_id: null, page: null })}>Reset filter</Button></div>
      <div className="mb-4 flex flex-wrap items-center gap-3"><Button onClick={() => setFrozen(frozen ? null : simulation)}>{frozen ? "Lanjutkan tampilan" : "Jeda tampilan"}</Button><Button onClick={() => copy(filtered.map(consoleText).join("\n"))}>Salin log tersanitasi</Button><Button onClick={() => { setCleared(simulation.now); setNotice("Tampilan lokal dibersihkan. Collector dan penyimpanan tidak diubah."); }}>Bersihkan tampilan lokal</Button><Button onClick={() => { setAuto(true); if (output.current) output.current.scrollTop = output.current.scrollHeight; }}>Ke event terbaru</Button><Button onClick={() => setExpanded(!expanded)}>{expanded ? "Kembalikan panel" : "Perluas panel"}</Button><Checkbox label="Autoscroll" checked={auto} onChange={e => setAuto(e.target.checked)}/><Checkbox label="Bungkus baris" checked={wrap} onChange={e => setWrap(e.target.checked)}/></div>
      <p className="mb-4 text-xs/5 text-muted" role="status">Collector belum terhubung · Browser lokal · {frozen ? "Dijeda" : "Snapshot"} · Buffer {events.length}/1.000 · {waiting} event baru · {simulation.dropped} keluar dari retensi contoh.</p>
      {simulation.dropped > 0 && <Alert tone="warning" title="Batas buffer / retensi lokal">Event paling lama sudah keluar dari buffer. <Button onClick={() => { setFrozen(null); setCleared(0); setNotice("Snapshot buffer saat ini dimuat ulang; event terbuang tidak direka ulang."); }}>Muat ulang snapshot contoh</Button></Alert>}
      {notice && <p className="my-3 text-sm" role="status">{notice}</p>}
      <Tabs label="Mode log runtime" value={mode} onValueChange={value => { if (output.current) positions.current[mode] = output.current.scrollTop; set({ mode: value }); }} items={[
        { value: "terminal", label: "Terminal", content: <div ref={output} tabIndex={0} role="region" aria-label="Output runtime contoh" onMouseUp={() => { if (window.getSelection()?.toString()) setAuto(false); }} onScroll={e => { positions.current.terminal = e.currentTarget.scrollTop; if (e.currentTarget.scrollHeight - e.currentTarget.scrollTop - e.currentTarget.clientHeight > 48) setAuto(false); }} className={cx("mt-4 overflow-auto rounded-control border border-control bg-canvas p-4 font-mono text-sm/6", expanded ? "h-[75dvh]" : "h-112", wrap ? "whitespace-pre-wrap wrap-anywhere" : "whitespace-pre")}>
          {!filtered.length ? <p>Belum ada pesan sesuai filter.</p> : filtered.map(event => <div key={event.id} className={cx("mb-3 rounded-control p-2", selected?.id === event.id && "bg-panel")}><pre className={cx("m-0 font-[inherit] text-[inherit]", wrap ? "whitespace-pre-wrap wrap-anywhere" : "whitespace-pre")}>{consoleText(event)}</pre><Button variant="ghost" size="sm" className="mt-1 font-sans text-xs" onClick={() => pick(event)} aria-label={`Detail event ${event.id}`}>Detail event</Button></div>)}
        </div> },
        { value: "structured", label: "Terstruktur", content: <UrlTable caption="Log runtime terstruktur" data={filtered} defaultSort="received_at" columns={[
          { accessorKey: "at", header: "Waktu sumber", cell: ({ row }) => new Date(row.original.at).toISOString() }, { accessorKey: "received_at", header: "Diterima collector (contoh)", cell: ({ row }) => new Date(row.original.received_at).toISOString() },
          { accessorKey: "level", header: "Level", cell: ({ row }) => <Badge tone={row.original.level === "ERROR" ? "error" : row.original.level === "WARNING" ? "warning" : "neutral"}>{row.original.level}</Badge> }, { accessorKey: "kind", header: "Jenis" }, { accessorKey: "logger", header: "Logger" }, { accessorKey: "message", header: "Pesan" }, { id: "detail", header: "Detail", cell: ({ row }) => <Button onClick={() => pick(row.original)}>Inspect</Button> },
        ]}/> },
      ]}/>
    </Panel>
    {(id || selected) && (selected ? <Panel title="Inspector event" description="Representasi tersanitasi yang sama dipakai pada tampilan dan copy."><dl className={`${detailList} [&_dd]:wrap-anywhere`}>{Object.entries({ log_event_id: selected.id, event_at: new Date(selected.at).toISOString(), received_at: new Date(selected.received_at).toISOString(), level: selected.level, kind: selected.kind, logger: selected.logger, instance: selected.instance, capture_kind: selected.capture_kind, request_id: selected.request_id || "Tidak ada korelasi request", truncation: "Tidak ada pada fixture terpilih" }).map(([key, value]) => <div className="contents" key={key}><dt className="text-muted">{key}</dt><dd>{value}</dd></div>)}</dl><pre className="overflow-auto text-sm whitespace-pre-wrap wrap-anywhere">{selected.message}</pre>{selected.frames.length > 0 && <details><summary className="min-h-11 cursor-pointer py-3">Traceback {selected.exception}</summary><pre className="text-sm whitespace-pre-wrap wrap-anywhere">{selected.frames.join("\n")}</pre></details>}<div className="mt-5 flex flex-wrap gap-4"><Button onClick={() => copy(consoleText(selected))}>Salin detail tersanitasi</Button>{selected.request_id ? <Link className={textLink} href={href(`/requests/${selected.request_id}`, { q: null, request_id: null, level: null })}>Lihat request terkait</Link> : <p className="text-sm text-muted">Lifecycle ini tidak memiliki request ID.</p>}<Button onClick={() => set({ event: null })} disabled={!!id}>Tutup inspector</Button></div></Panel> : <Alert tone="warning">Event tidak tersedia pada environment/rentang atau sudah keluar dari retensi. Tidak dibuat detail rekaan.</Alert>)}
  </>;
}
