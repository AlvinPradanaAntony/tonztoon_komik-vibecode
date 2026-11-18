"use client";

import { useRef, useState } from "react";
import { wrap, sectionLabel } from "./ui/styles";
import {
  Alert, Badge, Button, Card, Checkbox, Dialog, Drawer, Input, Panel,
  Select, StatusBadge, Table, Tabs, Textarea, useToast, type ToastPosition, type TableState, type TableColumn, type UiSize, type UiTone,
} from "./ui";

const modules = [
  { name: "Sesi admin", identity: "Identitas dan izin" },
  { name: "Monitoring API", identity: "Method + route template" },
  { name: "Katalog komik", identity: "Source + slug" },
];
const tones: UiTone[] = ["neutral", "info", "success", "warning", "error"];
const moduleColumns:TableColumn<(typeof modules)[number]>[]=[
  {id:'name',accessorFn:row=>`${row.name} ${row.identity}`,header:'Modul',meta:{rowHeader:true},
    cell:({row})=><>{row.original.name}<span className="block text-xs font-normal text-muted">{row.original.identity}</span></>},
  {id:'status',header:'Integrasi starter',enableSorting:false,cell:()=><StatusBadge status="unknown">Belum terhubung</StatusBadge>},
];
const toneLabels = { neutral: "Netral", info: "Informasi", success: "Sukses", warning: "Peringatan", error: "Error" };
const buttonVariants = ["primary", "secondary", "ghost", "info", "success", "warning", "error"] as const;

export function StarterPreview() {
  const { toast, dismissAll } = useToast();
  const [toastPosition, setToastPosition] = useState<ToastPosition>("top-right");
  const [query, setQuery] = useState("");
  const [tableState, setTableState] = useState<TableState>("ready");
  const [feedback, setFeedback] = useState("Belum ada aksi contoh yang dijalankan.");
  const [busy, setBusy] = useState(false);
  const [size, setSize] = useState<UiSize>("md");
  const [tone, setTone] = useState<UiTone>("neutral");
  const [forceInvalid, setForceInvalid] = useState(false);
  const [fieldsLoading, setFieldsLoading] = useState(false);
  const [name, setName] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [includeNote, setIncludeNote] = useState(true);
  const [formFeedback, setFormFeedback] = useState<"idle" | "success" | "error">("idle");
  const [dialogOpen, setDialogOpen] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [drawerSide, setDrawerSide] = useState<"start" | "end">("start");
  const [selectedComponent, setSelectedComponent] = useState("Belum dipilih");
  const nameRef = useRef<HTMLInputElement>(null);
  const nameError = forceInvalid || (submitted && !name.trim()) ? "Isi nama pemeriksaan contoh." : undefined;

  return <>
    <div className="mt-6 grid items-start gap-6 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
      <Panel title="Daftar contoh" description="Input, Select, Table, dan StatusBadge memakai kontrak bersama.">
        <div className="grid gap-4 sm:grid-cols-2">
          <Input label="Cari modul" type="search" value={query} onChange={(event) => setQuery(event.currentTarget.value)} placeholder="Nama atau identitas" />
          <Select label="Kondisi tabel" value={tableState} onChange={(event) => setTableState(event.currentTarget.value as TableState)}>
            <option value="ready">Normal</option><option value="loading">Memuat</option><option value="empty">Kosong</option><option value="error">Gagal</option>
          </Select>
        </div>
        <div className="mt-5">
          <Table caption="Modul rencana integrasi, bukan kesehatan layanan" data={modules} columns={moduleColumns}
            globalFilter={query} state={tableState} pageSize={2} getRowId={row=>row.name}
            emptyState={{title:query?'Modul tidak ditemukan':'Belum ada modul',icon:query?'search':'overview',
              description:query?'Coba nama atau identitas modul lain, atau reset pencarian.':'Tidak ada modul pada kondisi contoh ini. Reset tabel untuk melihat daftar modul.',
              action:<Button appearance="outline" onClick={()=>{setQuery('');setTableState('ready');}}>Reset tabel</Button>}}
            message={tableState==='loading'?'Contoh memuat; tidak ada request backend.':tableState==='error'?'Contoh gagal memuat; gunakan Coba lagi.':'Tidak ada modul pada kondisi atau pencarian ini.'}
            onRetry={()=>{setTableState('ready');setQuery('');}}/>
          {tableState !== "empty" && tableState !== "ready" && <Button className="mt-3" size="sm" onClick={() => { setQuery(""); setTableState("ready"); }}>Reset tabel</Button>}
        </div>
      </Panel>

      <Card title="Aksi dan status" description="Setiap tombol aktif hanya mengubah pesan contoh lokal.">
        <div className={wrap}>
          {buttonVariants.map((variant) => <Button key={variant} variant={variant} size="sm" onClick={() => setFeedback(`Varian ${variant} dipilih. Tidak ada perubahan backend.`)}>{variant}</Button>)}
        </div>
        <div className="mt-4"><Alert announce>{feedback}</Alert></div>
        <p className={sectionLabel}>Outline dan soft</p>
        <div className={wrap}>
          <Button appearance="outline" onClick={() => setFeedback("Tombol outline dipilih.")}>Outline</Button>
          <Button appearance="outline" aria-label="Aksi outline" onClick={() => setFeedback("Aksi ikon outline dipilih.")}><svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M12 19V5m-6 6 6-6 6 6" /></svg></Button>
          {tones.filter(entry => entry !== "neutral").map(entry => <Button key={entry} variant={entry as "info" | "success" | "warning" | "error"} appearance="soft" onClick={() => setFeedback(`Soft ${entry} dipilih.`)}>Soft {toneLabels[entry]}</Button>)}
        </div>
        <p className={sectionLabel}>Loading dan disabled</p>
        <div className={wrap}>
          <Button loading={busy} variant="success" aria-describedby="loading-demo-hint" onClick={() => setBusy(true)}>Proses contoh</Button>
          <Button size="sm" disabled={!busy} onClick={() => setBusy(false)}>Akhiri loading</Button>
          <Button disabled variant="error" aria-describedby="loading-demo-hint">Aksi nonaktif</Button>
        </div>
        <p id="loading-demo-hint" className="mt-2 text-xs text-muted">Proses contoh menjalankan loading lokal sampai Anda memilih Akhiri loading. Aksi nonaktif tidak tersedia pada pemeriksaan ini.</p>
        <p className={sectionLabel}>Badge status</p>
        <div className={wrap}>{tones.map((entry) => <Badge key={entry} tone={entry}>{toneLabels[entry]}</Badge>)}</div>
        <div className="mt-3 flex flex-wrap items-center gap-3"><Badge tone="success" appearance="outline">Outline sukses</Badge><Badge tone="error" appearance="solid">Solid error</Badge></div>
        <p className={sectionLabel}>Contoh StatusBadge</p>
        <div className={wrap}>{(["success", "warning", "error", "unknown", "loading", "disabled"] as const).map((status) => <StatusBadge key={status} status={status} size="sm" />)}</div>
      </Card>
    </div>

    <div className="mt-6 grid gap-6">
      <Panel title="Field dan validasi" description="Pengaturan berikut menguji props bersama. Validasi hanya berlaku pada contoh lokal ini.">
        <div className="grid items-start gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Select label="Ukuran komponen" value={size} onChange={(event) => setSize(event.currentTarget.value as UiSize)}>
            <option value="sm">Small, target sentuh 44 px</option><option value="md">Medium, 44 px</option><option value="lg">Large, 48 px</option>
          </Select>
          <Select label="Tone field" value={tone} onChange={(event) => setTone(event.currentTarget.value as UiTone)}>
            {tones.map((entry) => <option key={entry} value={entry}>{toneLabels[entry]}</option>)}
          </Select>
          <div><Checkbox label="Tampilkan invalid" checked={forceInvalid} onChange={(event) => setForceInvalid(event.currentTarget.checked)} />
            <Checkbox label="Tampilkan loading field" checked={fieldsLoading} onChange={(event) => setFieldsLoading(event.currentTarget.checked)} /></div>
        </div>
        <form className="mt-6" noValidate onSubmit={(event) => {
          event.preventDefault(); setSubmitted(true);
          if (!name.trim() || forceInvalid) { setFormFeedback("error"); nameRef.current?.focus(); }
          else setFormFeedback("success");
        }}>
          <div className="grid items-start gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Input ref={nameRef} label="Nama pemeriksaan" name="checkName" value={name} onChange={(event) => setName(event.currentTarget.value)}
              tone={tone} size={size} loading={fieldsLoading} error={nameError} hint="Nama hanya dipakai pada pemeriksaan lokal." required />
            <Select label="Sumber contoh" tone={tone} size={size} loading={fieldsLoading} invalid={forceInvalid}
              error={forceInvalid ? "Contoh pesan invalid untuk Select." : undefined} defaultValue="local">
              <option value="local">Fixture lokal</option><option value="other">Contoh alternatif</option>
            </Select>
            <Input label="Nilai baca saja" readOnly value="Pemeriksaan lokal" size={size} hint="Readonly tetap dapat difokuskan dan disalin." />
            <Input label="Input nonaktif" tone="error" disabled size={size} value="Tidak dapat diedit" hint="Disabled mengungguli tone error, tanpa mengurangi keterbacaan." />
            <Select label="Select nonaktif" tone="success" disabled size={size} defaultValue="locked"><option value="locked">Tidak dapat diganti</option></Select>
            <Checkbox label="Sertakan catatan contoh" checked={includeNote} onChange={(event) => setIncludeNote(event.currentTarget.checked)}
              tone={tone} size={size} loading={fieldsLoading} invalid={forceInvalid} error={forceInvalid ? "Contoh pesan invalid untuk Checkbox." : undefined} />
          </div>
          <div className="mt-4"><Textarea label="Catatan pemeriksaan" tone={tone} size={size} disabled={!includeNote}
            loading={fieldsLoading} invalid={forceInvalid} error={forceInvalid ? "Contoh pesan invalid untuk Textarea." : undefined}
            placeholder="Catatan contoh, tanpa informasi sensitif" /></div>
          <div className="mt-4 flex flex-wrap items-center gap-3"><Button type="submit" variant="primary" size={size} disabled={fieldsLoading}>Periksa isian</Button>
            <Button size={size} onClick={() => { setSubmitted(false); setName(""); setForceInvalid(false); setFormFeedback("idle"); nameRef.current?.focus(); }}>Reset form</Button></div>
          {formFeedback !== "idle" && <div className="mt-4"><Alert tone={formFeedback} announce>
            {formFeedback === "success" ? "Isian contoh valid. Tidak ada data yang disimpan ke backend." : "Periksa field yang ditandai invalid."}
          </Alert></div>}
        </form>
      </Panel>

      <Panel title="Pesan semantik" description="Warna status berasal dari tema bersama; style netral tidak menimpanya.">
        <div className="grid gap-4 sm:grid-cols-2">{tones.map((entry) => <Alert key={entry} tone={entry} title={toneLabels[entry]} className={entry === "error" ? "sm:col-span-2" : undefined}>Contoh pesan {toneLabels[entry].toLocaleLowerCase("id-ID")}, bukan status backend.</Alert>)}</div>
      </Panel>

      <Panel title="Tabs" description="Contoh lokal dengan penanda bergeser. Gunakan panah kiri/kanan, Home atau End untuk berpindah tab.">
        <Tabs label="Pengaturan contoh" className="max-w-lg" defaultValue="profile" items={[
          { value: "profile", label: "Profil", content: <Card title="Profil contoh" description="Isian ini hanya disimpan selama halaman terbuka.">
            <Input label="Nama tampilan contoh" placeholder="Masukkan nama tampilan" />
            <div className="mt-4"><Button variant="primary" onClick={() => toast({ title: "Profil contoh diperiksa", description: "Tidak ada data yang disimpan ke backend.", tone: "info" })}>Periksa profil</Button></div>
          </Card> },
          { value: "preferences", label: "Preferensi", content: <Card title="Preferensi contoh" description="Pilihan ini hanya untuk pemeriksaan komponen.">
            <Checkbox label="Sertakan ringkasan contoh" defaultChecked />
            <div className="mt-4"><Button onClick={() => toast({ title: "Preferensi contoh diperiksa", tone: "success" })}>Periksa preferensi</Button></div>
          </Card> },
          { value: "access", label: "Akses (nonaktif)", disabled: true, content: <p>Contoh tab nonaktif.</p> },
        ]} />
      </Panel>

      <Panel title="Toast" description="Notifikasi contoh lokal. Arahkan pointer atau fokus untuk membentangkan tumpukan dan menjeda waktu tampil.">
        <Select label="Posisi Toast" value={toastPosition} onChange={event => setToastPosition(event.currentTarget.value as ToastPosition)}>
          <option value="top-left">Atas kiri</option><option value="top-center">Atas tengah</option><option value="top-right">Atas kanan</option>
          <option value="bottom-left">Bawah kiri</option><option value="bottom-center">Bawah tengah</option><option value="bottom-right">Bawah kanan</option>
        </Select>
        <div className="mt-4 flex flex-wrap items-center gap-3">{tones.map(entry => <Button key={entry} onClick={() => toast({ title: `Notifikasi ${toneLabels[entry]}`, description: "Contoh lokal, tanpa perubahan backend.", tone: entry, position: toastPosition })}>Toast {toneLabels[entry]}</Button>)}</div>
        <div className="mt-3 flex flex-wrap items-center gap-3">
          <Button onClick={() => toast({ title: "Notifikasi singkat", position: toastPosition })}>Tanpa deskripsi</Button>
          <Button onClick={() => toast({ title: "Pratinjau pilihan", content: <p>Konten React lokal. Toast ini menunggu Anda menutupnya.</p>, position: toastPosition,
            action: { label: "Gunakan contoh", onClick: () => setFeedback("Aksi Toast dipilih. Tidak ada perubahan backend.") } })}>Dengan aksi dan konten</Button>
          <Button onClick={dismissAll}>Tutup semua Toast</Button>
        </div>
        <p className={sectionLabel}>Aksi async dan promise</p>
        <div className={wrap}>
          <Button onClick={() => {
            let attempts = 0;
            toast({ title: "Aksi async contoh", description: "Percobaan pertama gagal, berikutnya berhasil. Simulasi lokal.", position: toastPosition,
              action: { label: "Jalankan aksi", onClick: async () => {
                await new Promise(resolve => setTimeout(resolve, 800));
                if (++attempts === 1) throw new Error("Kegagalan contoh lokal");
                setFeedback("Aksi async Toast berhasil. Tidak ada perubahan backend.");
              } } });
          }}>Aksi async Toast</Button>
          {[false, true].map(fail => <Button key={String(fail)} onClick={() => {
            toast.promise(() => new Promise<string>((resolve, reject) => setTimeout(() => {
              if (fail) reject(new Error("Contoh proses gagal")); else resolve("Pemeriksaan lokal");
            }, 1800)), {
              position: toastPosition,
              loading: "Memproses contoh lokal…",
              success: result => ({ title: `${result} selesai`, description: "Promise berhasil. Tidak ada perubahan backend." }),
              error: { title: "Proses contoh gagal", description: "Promise ditolak dalam simulasi lokal." },
            });
          }}>{fail ? "Promise gagal" : "Promise berhasil"}</Button>)}
        </div>
      </Panel>

      <Panel title="Dialog dan drawer" description="Overlay terkontrol dengan dialog native, Escape, fokus terkurung, dan fokus kembali ke pemicu.">
        <div className="grid items-start gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Select label="Sisi drawer" value={drawerSide} onChange={(event) => setDrawerSide(event.currentTarget.value as "start" | "end")}>
            <option value="start">Awal</option><option value="end">Akhir</option>
          </Select>
          <div className={wrap}><Button onClick={() => setDialogOpen(true)}>Buka dialog</Button><Button onClick={() => setDrawerOpen(true)}>Buka drawer</Button></div>
          <Alert>Komponen dipilih: {selectedComponent}. Ini pilihan lokal, tanpa navigasi ke halaman yang belum dibangun.</Alert>
        </div>
      </Panel>
    </div>

    <Dialog open={dialogOpen} onOpenChange={setDialogOpen} title="Pemeriksaan dialog" description="Tidak ada perubahan backend dari dialog contoh ini."
      actions={<Button variant="primary" onClick={() => { setSelectedComponent("Dialog"); setDialogOpen(false); }}>Gunakan dialog contoh</Button>}>
      <Input label="Catatan dialog" placeholder="Isi catatan contoh" />
    </Dialog>
    <Drawer open={drawerOpen} onOpenChange={setDrawerOpen} side={drawerSide} title="Pilih komponen" description="Drawer contoh memakai primitive dialog native agar latar inert dan fokus tetap di panel.">
      <div className="grid gap-3">{["Button", "Input", "Table"].map((entry) => <Button key={entry} variant="ghost" onClick={() => { setSelectedComponent(entry); setDrawerOpen(false); }}>{entry}</Button>)}</div>
    </Drawer>
  </>;
}
