"use client";
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { Alert, Button, Panel, Select, Tabs, type TableColumn } from "@/components/ui";
import { effective, type Fields } from "@/lib/admin-data/types";
import { useWorkspace } from "@/lib/admin-data/demo-repository";
import { sourceRegistry } from "@/lib/demo/catalog";
import { DemoBoundary, DemoSearch, useQueryState } from "./demo-boundary";
import { PageTitle, detailList } from "./patterns";
import { textLink } from "@/components/ui/styles";
import { UrlTable } from "./url-table";
import { ComicReader } from "./comic-reader";
import { safeReturn } from "@/lib/admin-data/routes";
import { PreviewFeed } from "./preview-feed";
export function ComicPreview({ source, slug, chapter }: { source?: string; slug?: string; chapter?: string }) {
  const { params, pathname, set, href } = useQueryState(), workspace = useWorkspace();
  const comics = workspace.records.filter(r => r.kind === "comics" && !r.archived), comic = comics.find(r => effective(r).source_name === source && effective(r).slug === slug);
  const values = comic ? effective(comic) : null;
  const chapters = workspace.records.filter(r => r.kind === "chapters" && r.parentId === comic?.id && !r.archived).map<Fields & {id:string}>(r => ({ ...effective(r), id: r.id }));
  const detailPath = source && slug ? `/comic-preview/${encodeURIComponent(source)}/${encodeURIComponent(slug)}` : "/comic-preview";
  const current = `${pathname}${params.size ? `?${params}` : ""}`;
  const feedBack = safeReturn(params.get("feedReturn"), "/comic-preview");
  const chapterColumns: TableColumn<(typeof chapters)[number]>[] = [{ accessorKey: "title", header: "Chapter", cell: ({ row }) => <Link className={textLink} href={href(`${detailPath}/chapters/${row.original.chapter_number}`, { detailReturn: current })}>{row.original.title}</Link> }, { accessorKey: "chapter_number", header: "Nomor", sortFn: (a, b) => Number(a.original.chapter_number) - Number(b.original.chapter_number) }, { accessorKey: "total_images", header: "Gambar dari metadata" }];
  return <><PageTitle title={chapter ? "Reader diagnostik" : slug ? "Preview detail komik" : "Preview Komik"} description={chapter ? `${values?.title ?? "Komik"} · Chapter ${chapter}. HTTP, transfer dan decode diperiksa terpisah.` : "Latest, Popular dan pencarian source/global pada katalog contoh."} action={slug && <Link className={textLink} href={chapter ? safeReturn(params.get("detailReturn")??params.get('returnTo'), detailPath) : feedBack}>Kembali ke {chapter ? "detail" : "feed"}</Link>} />
    <DemoBoundary permission="preview:read">
      {source && !comic ? <Alert tone="error">Komik aktif tidak ditemukan pada identitas source + slug ini.</Alert> : chapter && comic ? <ComicReader key={`${comic.id}:${chapter}`} comic={comic} chapter={chapter} chapters={chapters} detailPath={detailPath}/> : values && comic ? <>
        <Panel title={values.title} description={`${values.source_name}/${values.slug} · ${chapters.length} metadata chapter aktif dari data contoh.`}><dl className={detailList}>{["genre", "status", "type", "author", "artist", "synopsis"].map(field => <div className="contents" key={field}><dt className="text-muted">{field}</dt><dd className="wrap-anywhere">{values[field] || "Belum tersedia"}</dd></div>)}</dl><p className="text-sm text-muted">Belum ada request backend atau gambar source nyata. Tidak menulis progress/bookmark pengguna.</p></Panel>
        <Panel title="Semua chapter" description="Semua metadata tersedia tanpa mengambil gambar setiap chapter. Nomor pecahan dipertahankan."><div className="mb-5 flex flex-wrap gap-4"><DemoSearch label="Cari nomor / judul chapter"/><Select label="Urutan chapter" value={params.get("order") ?? "asc"} onChange={e => set({ sort: "chapter_number", order: e.target.value, page: null })}><option value="asc">Nomor naik</option><option value="desc">Nomor turun</option></Select></div><UrlTable data={chapters.filter(r => `${r.chapter_number} ${r.title}`.toLowerCase().includes((params.get("q") ?? "").toLowerCase()))} columns={chapterColumns} caption="Seluruh chapter contoh" defaultSort="chapter_number" /></Panel>
      </> : <Panel title="Jelajahi feed contoh" description="Ranking Latest/Popular mengikuti urutan fixture prototype, bukan hasil ranking deployment."><Tabs compact hidePanels label="Feed preview" value={params.get("feed") === "popular" ? "popular" : "latest"} onValueChange={feed => set({ feed, page: null })} items={[{ value: "latest", label: "Latest", content: null }, { value: "popular", label: "Popular", content: null }]} /><div className="my-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><DemoSearch label="Cari judul komik"/><Select label="Scope source" value={params.get("source") ?? ""} onChange={e => set({ source: e.target.value, page: null })}><option value="">Semua source</option>{sourceRegistry.map(source => <option key={source.id} value={source.id}>{source.title}</option>)}</Select><Button onClick={() => set({ q: null, source: null, page: null })}>Reset pencarian</Button><Button onClick={() => set({ run: crypto.randomUUID(), q: null, page: null })}>Mulai sesi diagnosis baru</Button></div>
        <PreviewFeed returnTo={current} comics={(params.get("feed") === "popular" ? [...comics].reverse() : comics).map<Fields & {id:string}>(r => ({ ...effective(r), id: r.id })).filter(r => (!params.get("source") || r.source_name === params.get("source")) && r.title.toLowerCase().includes((params.get("q") ?? "").toLowerCase()))}/>{params.get("run") && <p className="mt-4 text-xs wrap-anywhere text-muted">Run contoh: {params.get("run")}. Tahap feed memakai metadata fixture, belum mengukur API.</p>}
      </Panel>}
    </DemoBoundary>
  </>;
}
