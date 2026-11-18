"use client";
import { useState } from "react";
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { Alert, Badge, Button, Dialog, Panel, Select, Table, Tabs, Input, type TableColumn } from "@/components/ui";
import { effective, profiles, readPermission, resourceLabels, type DemoRecord, type Fields, type ResourceKind } from "@/lib/admin-data/types";
import { demoRepository, useWorkspace } from "@/lib/admin-data/demo-repository";
import { safeReturn, type DataRoute } from "@/lib/admin-data/routes";
import { sourceRegistry } from "@/lib/demo/catalog";
import { DemoBoundary, DemoSearch, useQueryState } from "./demo-boundary";
import { PageTitle, detailList, numberCell } from "./patterns";
import { primaryActionLink, textLink } from "@/components/ui/styles";
import { UrlTable } from "./url-table";
import { ResourceEditor } from "./resource-editor";
type Row = Fields & { id: string };
const descriptions: Record<ResourceKind, string> = { comics: "Identitas source + slug tetap; metadata source, override dan efektif terpisah.", chapters: "Seluruh metadata chapter, termasuk nomor pecahan. Gambar tidak diambil pada daftar.", genres: "Nama editorial dapat diubah; slug unik tetap setelah create.", sources: "Registry baca saja. Statistik tersimpan tidak membuktikan health upstream.", accounts: "Akun nonadmin dan proyeksi profil minimum. Email tersamarkan.", helpdesk: "Antrean laporan/review, status penanganan, dan catatan internal.", audit: "Metadata tindakan tersanitasi, tanpa credential atau isi laporan/library." };
const detailColumns: TableColumn<{ id: string; source: string; override: string; value: string }>[] = [{ accessorKey: "id", header: "Field", meta: { rowHeader: true } }, { accessorKey: "source", header: "Source" }, { accessorKey: "override", header: "Override" }, { accessorKey: "value", header: "Efektif" }];
export function DataPage({ route }: { route: DataRoute }) {
  const workspace = useWorkspace(), { params, pathname, set, href } = useQueryState();
  const { kind, mode, parentId, id } = route;
  const record = workspace.records.find(r => r.kind === kind && r.id === id);
  const parent = workspace.records.find(r => r.kind === "comics" && r.id === parentId);
  const canWrite = profiles[workspace.profile].permissions.includes(kind === "accounts" ? "users:manage" : kind === "helpdesk" ? "helpdesk:manage" : "catalog:write") && !["sources", "audit"].includes(kind);
  const [confirm, setConfirm] = useState<string | null>(null), [message, setMessage] = useState("");
  const base = parentId ? `/data/comics/${parentId}/chapters` : `/data/${kind}`;
  const currentHref = `${pathname}${params.size ? `?${params}` : ""}`;
  const back = safeReturn(params.get("returnTo"), mode === "edit" ? `/data/${kind}/${id}` : base);
  const related = (path: string) => href(path, { returnTo: currentHref, q: null, page: null, sort: null, order: null, status: null, genre: null, source: null });
  const detailHref = (itemId: string) => href(`/data/${kind}/${itemId}`, { returnTo: currentHref });
  const values = record ? effective(record) : {};
  function applyAction() {
    if (!record || !confirm) return;
    const response = demoRepository.mutate({ kind, id: record.id, expectedRevision: record.revision, operationId: crypto.randomUUID(), action: confirm.startsWith("reset:") ? "reset" : confirm as "archive" | "restore", resetField: confirm.startsWith("reset:") ? confirm.slice(6) : undefined });
    setMessage(response.message); setConfirm(null);
  }
  const all = workspace.records.filter(r => r.kind === kind && (!parentId || r.parentId === parentId));
  const q = (params.get("q") ?? "").toLowerCase();
  const rows: Row[] = all.map<Row>(r => ({ ...effective(r), id: r.id, status: r.archived ? "archived" : effective(r).status ?? "active" })).filter(row =>
    Object.values(row).some(value => value.toLowerCase().includes(q)) &&
    (!params.get("source") || row.source_name === params.get("source")) &&
    (!params.get("status") || row.status === params.get("status")) &&
    (!params.get("genre") || row.genre === params.get("genre")) &&
    (!params.get("category") || row.category === params.get("category")) &&
    (!params.get("result") || row.result === params.get("result")) &&
    (!params.get("actor") || row.actor === params.get("actor")) &&
    (!params.get("action") || row.action === params.get("action")) &&
    (!params.get("request_id") || row.request_id === params.get("request_id")) &&
    (!params.get("from") || row.observed_at >= `${params.get("from")}T00:00:00Z`) &&
    (!params.get("to") || row.observed_at <= `${params.get("to")}T23:59:59Z`));
  const column = (key: string, label: string): TableColumn<Row> => ({ accessorKey: key, header: label, meta: {className: key==='total_images'?numberCell:undefined}, cell: ({ row }) => row.original[key] || "Belum tersedia" });
  const statusColumn: TableColumn<Row> = { accessorKey: "status", header: "Status", cell: ({ row }) => <Badge tone={["archived", "banned", "closed"].includes(row.original.status) ? "neutral" : ["open", "pending", "in_progress"].includes(row.original.status) ? "warning" : "success"}>{row.original.status}</Badge> };
  const columns: TableColumn<Row>[] = [
    { accessorKey: "title", header: kind === "accounts" ? "Username" : kind === "audit" ? "Waktu / tindakan" : "Judul / identitas", meta: { rowHeader: true }, cell: ({ row }) => <Link className={`${textLink} flex-col items-start gap-1`} href={detailHref(row.original.id)}>{row.original.title}<small className="block text-xs text-muted">{kind === "comics" ? `${row.original.source_name}/${row.original.slug}` : kind === "audit" ? row.original.observed_at : row.original.id}</small></Link> },
    ...(kind === "comics" ? [column("source_name", "Source"), statusColumn, column("genre", "Genre"), { id: "chapters", header: "Chapter", meta:{className:numberCell}, cell: ({ row }: { row: { original: Row } }) => workspace.records.filter(r => r.kind === "chapters" && r.parentId === row.original.id).length }] :
      kind === "chapters" ? [{ accessorKey: "chapter_number", header: "Nomor", sortFn: (a: {original:Row}, b: {original:Row}) => Number(a.original.chapter_number) - Number(b.original.chapter_number) } as TableColumn<Row>, column("release_date", "Rilis"), column("total_images", "Halaman"), statusColumn] :
      kind === "genres" ? [column("slug", "Slug"), { id: "relations", header: "Komik terkait", meta:{className:numberCell}, cell: ({ row }: { row: { original: Row } }) => workspace.records.filter(r => r.kind === "comics" && effective(r).genre === row.original.title).length }] :
      kind === "sources" ? [column("source_name", "Key registry"), statusColumn, column("observed_at", "Observasi")] :
      kind === "accounts" ? [column("display_name", "Nama tampilan"), column("email_masked", "Email tersamarkan"), statusColumn] :
      kind === "helpdesk" ? [column("category", "Kategori"), statusColumn] : [column("actor", "Aktor"), column("resource", "Resource"), column("action", "Aksi"), column("result", "Hasil"), column("request_id", "Request ID")]),
    ...(canWrite ? [{ id: "edit", header: "Aksi", enableSorting: false, cell: ({ row }: { row: { original: Row } }) => <Link className={textLink} href={related(`/data/${kind}/${row.original.id}/edit`)}>{kind === "helpdesk" ? "Tangani" : "Edit metadata"}</Link> }] : []),
  ];
  const filter = (key: string, label: string, options: string[]) => <Select key={key} label={label} value={params.get(key) ?? ""} onChange={e => set({ [key]: e.target.value, page: null })}><option value="">Semua {label.toLowerCase()}</option>{options.map(value => <option key={value}>{value}</option>)}</Select>;
  return <><PageTitle title={`${mode === "list" ? "" : mode === "new" ? "Tambah " : mode === "edit" ? "Editor " : mode === "library" ? "Library " : "Detail "}${resourceLabels[kind]}${parent ? ` · ${effective(parent).title}` : ""}`} description={descriptions[kind]} action={mode === "list" && canWrite && ["comics","chapters","genres","accounts"].includes(kind) ? <Link className={primaryActionLink} href={related(`${base}/new`)}>Tambah {kind === "accounts" ? "akun nonadmin" : resourceLabels[kind].toLowerCase()}</Link> : mode !== "list" ? <Link className={textLink} href={back}>Kembali</Link> : undefined} />
    <DemoBoundary permission={mode === "library" ? "users:inspect-library" : readPermission(kind)}>
      {message && <Alert tone="success">{message}</Alert>}
      {parentId && !parent ? <Alert tone="error">Komik contoh tidak ditemukan.</Alert> : mode !== "list" && mode !== "new" && !record ? <Alert tone="error" title="Resource tidak ditemukan">ID tidak ada dalam dataset contoh ini. <Link href={base} className={textLink}>Kembali ke daftar</Link></Alert> : mode === "edit" || mode === "new" ? canWrite ? <ResourceEditor key={`${kind}:${id ?? `new:${parentId}`}`} kind={kind} record={record} parentId={parentId} backHref={back} /> : <Alert tone="error">Profil contoh tidak memiliki izin tulis.</Alert> : mode === "library" && record ? <Library account={record} /> : mode === "list" ? <Panel title={resourceLabels[kind]} description={`${rows.length} dari ${all.length} resource contoh. Filter dan urutan tersimpan pada URL.`}>
        <div className="mb-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><DemoSearch label={`Cari ${resourceLabels[kind]}`} />
          {kind === "comics" && <>{filter("source", "Source", sourceRegistry.map(source => source.id))}{filter("genre", "Genre", ["Action", "Fantasy", "Adventure"])}</>}
          {["comics", "chapters", "sources", "accounts", "helpdesk"].includes(kind) && filter("status", "Status", kind === "comics" ? ["ongoing", "completed", "hiatus", "archived"] : kind === "chapters" ? ["active", "archived"] : kind === "sources" ? ["active", "backup"] : kind === "accounts" ? ["active", "pending", "banned"] : ["open", "in_progress", "resolved", "closed"])}
          {kind === "helpdesk" && filter("category", "Kategori", ["report", "review"])}
          {kind === "audit" && <>{filter("result", "Hasil", ["success", "conflict", "pending", "simulated"])}{filter("actor", "Aktor", ["admin-contoh", "operator-contoh"])}{filter("action", "Aksi", ["update", "archive", "restore", "status", "profile", "create", "reset"])}<Input type="date" label="Dari UTC" value={params.get("from") ?? ""} onChange={e => set({ from: e.target.value, page: null })} /><Input type="date" label="Sampai UTC" value={params.get("to") ?? ""} onChange={e => set({ to: e.target.value, page: null })} /><DemoSearch label="Request ID persis" queryKey="request_id" /></>}
          <Button onClick={() => set({ q: null, source: null, status: null, genre: null, category: null, result: null, actor: null, action: null, request_id: null, from: null, to: null, sort: null, order: null, page: null })}>Reset filter</Button>
        </div><UrlTable data={rows} columns={columns} caption={`${resourceLabels[kind]} contoh`} defaultSort={kind === "chapters" ? "chapter_number" : "title"} />
      </Panel> : record && <>
        <Panel title={values.title || record.id} description={`ID ${record.id} · revision ${record.revision} · ${record.archived ? "Arsip" : values.status ?? "Aktif"}`} actions={canWrite && <Link className={textLink} href={related(`/data/${kind}/${record.id}/edit`)}>{kind === "helpdesk" ? "Tangani laporan" : "Edit metadata"}</Link>}>
          {kind === "comics" ? <Tabs label="Detail komik" value={params.get("tab") ?? "metadata"} onValueChange={tab => set({ tab })} items={[
            { value: "metadata", label: "Metadata", content: <><Table caption="Nilai source, override dan efektif" columns={detailColumns} data={Object.keys(record.source).map(field => ({ id: field, source: record.source[field] || "Belum tersedia", override: record.override[field] ?? "Belum ada override", value: values[field] || "Belum tersedia" }))} pagination={false} />{canWrite && Object.keys(record.override).map(field => <Button key={field} className="me-3 mt-3" onClick={() => setConfirm(`reset:${field}`)}>Kembalikan {field} ke source</Button>)}</> },
            { value: "relations", label: "Chapter / relasi", content: <div className="space-y-4 py-4"><p>{workspace.records.filter(r => r.parentId === record.id).length} metadata chapter contoh. Arsip mempertahankan relasi dan progress.</p><Link className={textLink} href={related(`/data/comics/${record.id}/chapters`)}>Buka semua chapter</Link><p>Gambar tersimpan sebagai JSONB per chapter.</p></div> },
            { value: "activity", label: "Aktivitas", content: <div className="py-4"><Link className={textLink} href={related("/data/audit") + `&q=${encodeURIComponent(`comics:${record.id}`)}`}>Lihat audit resource</Link></div> },
          ]} /> : <dl className={`${detailList} grid-cols-[minmax(0,1fr)_minmax(0,2fr)] [&_dd]:wrap-anywhere`}>{Object.entries(values).filter(([field]) => !["before", "after"].includes(field)).map(([field, value]) => <div key={field} className="contents"><dt className="text-muted">{field.replaceAll("_", " ")}</dt><dd>{value || "Belum tersedia"}</dd></div>)}</dl>}
          {kind === "chapters" && <div className="flex flex-wrap gap-4"><Link className={textLink} href={related(`/data/comics/${values.comic_id}/chapters`)}>Kembali ke chapter komik</Link><Link className={textLink} href={related(`/comic-preview/${effective(workspace.records.find(r => r.id === values.comic_id && r.kind === "comics")!).source_name}/${effective(workspace.records.find(r => r.id === values.comic_id && r.kind === "comics")!).slug}/chapters/${values.chapter_number}`)}>Buka reader contoh</Link><p className="text-sm text-muted">{values.total_images ?? "0"} item images JSONB. Bytes gambar belum diuji.</p></div>}
          {kind === "accounts" && <div className="space-y-4"><p className="text-sm">Bookmark 4 · Progress 3 · Koleksi 2 · Riwayat 5 (seluruhnya contoh). Token/sesi tidak dikembalikan.</p>{profiles[workspace.profile].permissions.includes("users:inspect-library") && <Link className={textLink} href={related(`/data/accounts/${record.id}/library`)}>Periksa library terbatas</Link>}</div>}
          {kind === "sources" && <div className="flex flex-wrap gap-4"><Link className={textLink} href={`/data/comics?source=${record.id}`}>Katalog source</Link><Link className={textLink} href={`/comic-preview?source=${record.id}`}>Preview source</Link></div>}
          {kind === "genres" && <Link className={textLink} href={`/data/comics?genre=${encodeURIComponent(values.title)}`}>Lihat komik terkait</Link>}
          {kind === "audit" && <><Table caption="Diff katalog tersanitasi" data={values.before || values.after ? [{ id: "title", before: values.before, after: values.after }] : []} columns={[{ accessorKey: "id", header: "Field" }, { accessorKey: "before", header: "Sebelum" }, { accessorKey: "after", header: "Sesudah" }]} pagination={false} /><p className="mt-4 text-sm text-muted">{values.request_id ? "Request ID hanya referensi fixture audit. Detail request tidak tersedia pada dataset monitoring ini." : "Perubahan lokal tidak membuat request/backend log rekaan."}</p></>}
        </Panel>
        {canWrite && ["comics", "chapters"].includes(kind) && <Panel title="Arsip dan pemulihan" description="Arsip tidak menghapus resource, relasi atau progress."><Button variant={record.archived ? "secondary" : "warning"} onClick={() => setConfirm(record.archived ? "restore" : "archive")}>{record.archived ? "Pulihkan" : "Arsipkan"} {values.title}</Button></Panel>}
      </>}
    </DemoBoundary>
    <Dialog open={!!confirm} onOpenChange={open => { if (!open) setConfirm(null); }} title={`${confirm === "archive" ? "Arsipkan" : confirm === "restore" ? "Pulihkan" : "Kembalikan override"} ${values.title ?? "resource"}?`} actions={<><Button onClick={() => setConfirm(null)}>Batal</Button><Button variant="primary" onClick={applyAction}>Konfirmasi contoh</Button></>}><p>{confirm === "archive" ? `${values.title} dan ${kind === "comics" ? workspace.records.filter(r => r.parentId === record?.id).length : 0} metadata chapter terkait tidak tampil pada read service publik setelah integrasi. Relasi dan progress tetap disimpan.` : confirm === "restore" ? "Resource kembali ke status sebelum diarsipkan. Identitas dan relasi tetap." : "Override field terpilih dihapus; nilai efektif mengikuti source."}</p><p className="mt-4 text-sm text-muted">Tindakan ini hanya mengubah data contoh frontend.</p></Dialog>
  </>;
}
function Library({ account }: { account: DemoRecord }) {
  const { params, set } = useQueryState();
  const rows = ["bookmark", "progress", "collection", "history"].flatMap((relation, i) => Array.from({ length: [4, 3, 2, 5][i] }, (_, n) => ({ id: `${relation}-${n}`, title: `Komik Contoh ${String.fromCharCode(65 + n)}`, relation, position: relation === "progress" ? "Chapter 12.5 · page 2 (contoh)" : "Relasi contoh baca saja" })));
  return <Panel title={`Library terbatas · ${effective(account).title}`} description="Proyeksi investigasi contoh. Tidak mengubah progress, bookmark, histori, atau download."><div className="mb-4 grid gap-4 sm:grid-cols-2"><DemoSearch label="Cari relasi library"/><Select label="Jenis relasi" value={params.get("relation") ?? ""} onChange={e => set({ relation: e.target.value, page: null })}><option value="">Semua relasi</option>{["bookmark", "progress", "collection", "history"].map(value => <option key={value}>{value}</option>)}</Select></div><UrlTable caption="Relasi library contoh" data={rows.filter(r => (!params.get("relation") || r.relation === params.get("relation")) && r.title.toLowerCase().includes((params.get("q") ?? "").toLowerCase()))} columns={[{ accessorKey: "relation", header: "Jenis relasi" }, { accessorKey: "title", header: "Resource" }, { accessorKey: "position", header: "Posisi / metadata minimum" }]} /></Panel>;
}
