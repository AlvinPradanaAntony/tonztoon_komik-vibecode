"use client";
import { useState } from "react";
import { Panel, Table, Tabs } from "@/components/ui";
import { demoTime } from "@/lib/demo/overview-simulation";
import type { RequestRow } from "@/lib/monitoring/demo-adapter";
export function EndpointCharts({ rows, lower, upper }: { rows: RequestRow[]; lower: number; upper: number }) {
  const [metric, setMetric] = useState("traffic");
  const buckets = Array.from({ length: 10 }, (_, i) => { const from = lower + i * (upper - lower) / 10, to = from + (upper - lower) / 10, data = rows.filter(r => r.at > from && r.at <= to), sorted = data.map(r => r.duration).sort((a, b) => a - b); return { id: String(from), time: demoTime(from), count: data.length, p95: sorted.length ? sorted[Math.ceil(sorted.length * .95) - 1] : null }; });
  const max = Math.max(1, ...buckets.map(b => metric === "traffic" ? b.count : b.p95 ?? 0));
  const histogram = [100, 250, 500, 1000, 2000, Infinity].map((limit, i, limits) => ({ id: String(limit), bucket: `${i ? `>${limits[i - 1]}` : "0"} sampai ${limit === Infinity ? "+∞" : limit} ms`, count: rows.filter(r => r.duration <= limit && (!i || r.duration > limits[i - 1])).length }));
  return <div className="mb-6 grid gap-6 xl:grid-cols-2">
    <Panel title="Trafik dan latensi">
      <Tabs compact hidePanels label="Metrik endpoint" value={metric} onValueChange={setMetric} items={[{ value: "traffic", label: "Trafik", content: null }, { value: "latency", label: "Latensi", content: null }]} />
      <svg viewBox="0 0 600 220" role="img" aria-label={metric === "traffic" ? "Jumlah request per bucket" : "p95 milidetik per bucket"} className="my-5 w-full">
        <text x="20" y="20" className="fill-muted text-sm">{metric === "traffic" ? "Request / bucket" : "p95 ms / bucket"}</text>
        {buckets.map((b, i) => <rect key={b.id} x={25 + i * 56} y={185 - (metric === "traffic" ? b.count : b.p95 ?? 0) / max * 140} width="32" height={(metric === "traffic" ? b.count : b.p95 ?? 0) / max * 140} className="fill-(--chart)"><title>{`${b.time}: ${metric === "traffic" ? b.count : b.p95 ?? "Belum tersedia"}`}</title></rect>)}
        <text x="20" y="215" className="fill-muted text-sm">{demoTime(lower)}</text><text x="500" y="215" className="fill-muted text-sm">{demoTime(upper)}</text>
      </svg>
      <details><summary className="min-h-11 cursor-pointer py-3 text-sm">Data grafik</summary><Table caption="Bucket endpoint" data={buckets} columns={[{ accessorKey: "time", header: "Waktu" }, { accessorKey: "count", header: "Request" }, { accessorKey: "p95", header: "p95 ms", cell: ({ row }) => row.original.p95 ?? "Belum tersedia" }]} pagination={false}/></details>
    </Panel>
    <Panel title="Histogram durasi" description={`${rows.length} sampel contoh, durasi body final.`}><Table caption="Histogram nonkumulatif" data={histogram} columns={[{ accessorKey: "bucket", header: "Bucket" }, { accessorKey: "count", header: "Sampel" }]} pagination={false}/></Panel>
  </div>;
}
