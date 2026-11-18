"use client";
import { useEffect, useRef, useState } from "react";
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { Alert, Button, Dialog, Input, Panel, Select, Table, Textarea, type TableColumn } from "@/components/ui";
import { demoRepository } from "@/lib/admin-data/demo-repository";
import { effective, resourceLabels, type DemoRecord, type Fields, type MutationResult, type ResourceKind } from "@/lib/admin-data/types";
import { formFields, initialValues, validateFields } from "@/lib/admin-data/forms";
import { textLink } from "@/components/ui/styles";
const diffColumns: TableColumn<{ id: string; before: string; after: string }>[] = [{ accessorKey: "id", header: "Field", meta: { rowHeader: true } }, { accessorKey: "before", header: "Sebelum" }, { accessorKey: "after", header: "Sesudah" }];
export function ResourceEditor({ kind, record, parentId, backHref }: { kind: ResourceKind; record?: DemoRecord; parentId?: string; backHref: string }) {
  const creating = !record, initial = record ? effective(record) : initialValues(kind, parentId);
  const [values, setValues] = useState<Fields>(initial), [version, setVersion] = useState(record?.revision ?? 0);
  const [errors, setErrors] = useState<Fields>({}), [preview, setPreview] = useState(false), [discard, setDiscard] = useState(false);
  const [outcome, setOutcome] = useState("success"), [result, setResult] = useState<MutationResult | null>(null), [notice, setNotice] = useState("");
  const [email, setEmail] = useState(""), [password, setPassword] = useState("");
  const operation = useRef<string | null>(null), draftKey = `tt-demo-draft:${kind}:${record?.id ?? `new:${parentId ?? ""}`}`;
  const summary = useRef<HTMLDivElement>(null);
  const dirty = JSON.stringify(values) !== JSON.stringify(initial);
  useEffect(() => { if (!dirty) return; const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); }; window.addEventListener("beforeunload", warn); return () => window.removeEventListener("beforeunload", warn); }, [dirty]);
  const saveDraft = (draft: Fields) => { try { sessionStorage.setItem(draftKey, JSON.stringify(draft)); } catch { setNotice("Penyimpanan draft sesi tidak tersedia. Form tetap dapat digunakan."); } };
  function update(key: string, value: string) { const next = { ...values, [key]: value }; setValues(next); saveDraft(next); operation.current = null; setResult(null); }
  function validate() {
    const next = validateFields(kind, values);
    if (creating && kind === "accounts") { if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) next.email = "Email tidak valid."; if (password.length < 8) next.password = "Password awal minimal 8 karakter."; }
    setErrors(next);
    if (Object.keys(next).length) { requestAnimationFrame(() => summary.current?.focus()); return false; }
    return true;
  }
  const changes = (formFields[kind] ?? []).filter(field => (values[field.key] ?? "") !== (creating ? "" : initial[field.key] ?? "")).map(field => ({ id: field.key, before: creating ? "Belum ada" : initial[field.key] || "Kosong", after: values[field.key] || "Kosong" }));
  function clearConfirmedDraft(){setPassword('');setEmail('');try{sessionStorage.removeItem(draftKey);}catch{}}
  function reconcile(){
    if(!result)return;
    const response=demoRepository.reconcile(result.operationId);setResult(response);
    if(response.status==='succeeded'){clearConfirmedDraft();if(record)setVersion(demoRepository.getSnapshot().records.find(item=>item.kind===kind&&item.id===record.id)?.revision??version);}
  }
  function commit() {
    if (!validate()) { setPreview(false); return; }
    const id = record?.id ?? (kind === "chapters" ? `${values.comic_id}-${values.chapter_number}` : `local-${operation.current ?? crypto.randomUUID()}`);
    operation.current ??= crypto.randomUUID();
    const safeValues = Object.fromEntries((formFields[kind] ?? []).map(field => [field.key, values[field.key] ?? ""]));
    if (kind === "accounts" && creating) { safeValues.role = "reader"; safeValues.email_masked = `${email.slice(0, 1)}***@${email.split("@")[1]}`; }
    const response = demoRepository.mutate({ operationId: operation.current, kind, id, expectedRevision: version, values: safeValues, action: creating ? "create" : "update" }, outcome);
    setResult(response); setPreview(false);
    if (response.status === "succeeded") { setVersion(demoRepository.getSnapshot().records.find(r => r.id === id && r.kind === kind)?.revision ?? version); clearConfirmedDraft(); }
  }
  const reload = () => { const latest = demoRepository.getSnapshot().records.find(r => r.kind === kind && r.id === record?.id); if (latest) { setValues(effective(latest)); setVersion(latest.revision); setErrors({}); setResult(null); operation.current = null; setNotice("Versi terbaru contoh dimuat. Draft tersimpan masih dapat dipulihkan."); } };
  return <Panel title={`${creating ? "Tambah" : "Editor"} ${resourceLabels[kind].toLowerCase()}`} description={`Revision ${version}. Perubahan hanya simulasi lokal, tidak dikirim ke backend.`}>
    {result && <Alert tone={result.status === "succeeded" ? "success" : "warning"} title={result.message}><code className="text-xs wrap-anywhere">{result.operationId}</code>{result.status === "pending" && <Button onClick={reconcile}>Periksa status tindakan contoh</Button>}{result.status === "conflict" && <Button onClick={reload}>Muat versi terbaru</Button>}</Alert>}
    {notice && <p role="status" className="my-4 text-sm">{notice}</p>}
    <form noValidate onSubmit={e => { e.preventDefault(); if (validate()) setPreview(true); }} className="mt-5 space-y-5">
      {Object.values(errors).some(Boolean) && <div ref={summary} tabIndex={-1} role="alert" className="rounded-control border border-danger p-4"><p className="font-semibold">Periksa field berikut</p><ul className="mt-2 list-inside list-disc">{Object.entries(errors).filter(([,error])=>!!error).map(([field, error]) => <li key={field}><a href={`#editor-${field}`} className={textLink}>{error}</a></li>)}</ul></div>}
      <div className="grid gap-5 sm:grid-cols-2">{(formFields[kind] ?? []).map(field => {
        const immutable = !creating && !!field.immutable || field.key==='comic_id'&&!!parentId;
        const props = { id: `editor-${field.key}`, label: field.label, value: values[field.key] ?? "", error: errors[field.key], required: field.required, disabled: result?.status==='pending', hint: immutable ? "Tetap setelah dibuat." : undefined, onBlur: () => setErrors(previous => ({ ...previous, [field.key]: validateFields(kind, values)[field.key] ?? "" })), onChange: (event: { target: { value: string } }) => update(field.key, event.target.value) };
        return field.options && !immutable ? <Select {...props} key={field.key}>{field.options.map(value => <option key={value}>{value}</option>)}</Select> : field.type === "textarea" ? <Textarea {...props} key={field.key} fieldClassName="sm:col-span-2" rows={5} maxLength={field.max} /> : <Input {...props} key={field.key} type={field.type ?? "text"} step={field.type === "number" ? "any" : undefined} readOnly={immutable} maxLength={field.max} />;
      })}{creating && kind === "accounts" && <><Input id="editor-email" label="Email untuk akun contoh" type="email" autoComplete="off" required value={email} error={errors.email} onChange={e => setEmail(e.target.value)} /><Input id="editor-password" label="Password awal contoh" type="password" autoComplete="new-password" required minLength={8} value={password} error={errors.password} onChange={e => setPassword(e.target.value)} hint="Email lengkap dan password tidak masuk draft atau audit." /></>}</div>
      <details><summary className="min-h-11 cursor-pointer py-3 text-sm">Skenario penyimpanan contoh</summary><div className="space-y-4"><Select label="Hasil submit contoh" value={outcome} onChange={e => { setOutcome(e.target.value); operation.current = null; }}><option value="success">Berhasil lokal</option><option value="invalid">Validasi server ditolak</option><option value="conflict">Konflik versi 409</option><option value="pending">Hasil belum pasti / rekonsiliasi</option></Select>{record && <Button onClick={() => { demoRepository.mutate({ kind, id: record.id, expectedRevision: record.revision, values: { title: `${initial.title ?? ""} (versi terbaru contoh)` }, action: "update", operationId: crypto.randomUUID() }); setNotice("Versi resource contoh berubah. Draft form tetap utuh."); }}>Simulasikan perubahan admin lain</Button>}</div></details>
      <div className="flex flex-wrap gap-3"><Button type="submit" variant="primary" disabled={result?.status === "pending" || result?.status === "succeeded"}>Periksa perubahan</Button><Button onClick={() => { try { const draft = JSON.parse(sessionStorage.getItem(draftKey) ?? "null"); if (draft && typeof draft === "object") { setValues(Object.fromEntries((formFields[kind] ?? []).map(field => [field.key, typeof draft[field.key] === "string" ? draft[field.key] : initial[field.key] ?? ""]))); setNotice("Draft sesi dipulihkan."); } else setNotice("Belum ada draft tersimpan."); } catch { setNotice("Draft sesi tidak dapat dibaca."); } }}>Pulihkan draft sesi</Button><Button onClick={async () => { try { await navigator.clipboard.writeText(JSON.stringify(values, null, 2)); setNotice("Draft tanpa credential disalin."); } catch { setNotice("Clipboard tidak tersedia."); } }}>Salin draft aman</Button><Button onClick={() => setDiscard(true)}>Batal</Button></div>
      <p className="text-xs/5 text-muted">{kind === "comics" ? "Rating, view, identitas source, dan timestamp sistem tetap baca." : kind === "chapters" ? "Gambar JSONB dan generated field tetap baca. Nomor pecahan dipertahankan." : kind === "accounts" ? "Role tetap reader nonadmin. Tidak ada grant role atau impersonasi." : "Data contoh untuk memeriksa alur editorial."}</p>
    </form>
    <Dialog open={preview} onOpenChange={setPreview} title={`Preview perubahan ${values.title || resourceLabels[kind]}`} actions={<><Button onClick={() => setPreview(false)}>Kembali edit</Button><Button variant="primary" onClick={commit}>Simpan contoh</Button></>}><Table caption="Perbandingan nilai draft" columns={diffColumns} data={changes} pagination={false} getRowId={row => row.id} /><p className="mt-4 text-sm text-muted">{creating && kind === "accounts" ? "Email dan password tidak disertakan dalam preview, draft, atau audit." : "Preview lokal. Tidak membuktikan commit backend."}</p></Dialog>
    <Dialog open={discard} onOpenChange={setDiscard} title={dirty ? "Tinggalkan draft?" : "Kembali ke resource"} actions={<><Button onClick={() => setDiscard(false)}>Lanjut edit</Button><Link className={textLink} href={backHref}>Kembali, pertahankan draft sesi</Link></>}><p>Draft editorial yang tersedia pada sesi dapat dipulihkan. Email dan password tidak disimpan.</p></Dialog>
    {result?.status === "succeeded" && <Link className={`${textLink} mt-5 inline-flex min-h-11 items-center`} href={backHref}>Kembali ke daftar / detail</Link>}
  </Panel>;
}
