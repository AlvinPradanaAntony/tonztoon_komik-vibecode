export type PageState = "belum diminta" | "mengantre" | "memuat" | "berhasil" | "gagal" | "dibatalkan";
export type ReaderPage = { page: number; state: PageState; attempt: number; url: string; http: number | null; type: string; bytes: number | null; transfer: number | null; decode: number | null; width: number | null; height: number | null; blobUrl: string; message: string };
type ReaderSnapshot = { pages: ReaderPage[]; timeline: { id: string; at: string; page: number; attempt: number; message: string }[]; runId: string; stopped: boolean };
export function validateImagePayload(pages: { page: number }[], total: number) { const errors: string[] = []; if (!pages.length) errors.push("Payload images kosong."); if (pages.length !== total) errors.push("Jumlah item tidak sama dengan total."); if (new Set(pages.map(p => p.page)).size !== pages.length) errors.push("Nomor page duplikat."); if (pages.some((p, i) => p.page !== i + 1)) errors.push("Nomor page hilang atau urutan tidak valid."); return errors; }
export class ReaderController {
  private snapshot: ReaderSnapshot;
  private listeners = new Set<() => void>();
  private queue: { page: number; scenario: string }[] = [];
  private active = new Map<number, AbortController>();
  private epoch = 0;
  constructor(runId = "") { this.snapshot = {...this.initial(),runId}; }
  private initial(): ReaderSnapshot { return { pages: [1, 2, 3].map(page => ({ page, state: "belum diminta", attempt: 0, url: "", http: null, type: "", bytes: null, transfer: null, decode: null, width: null, height: null, blobUrl: "", message: "" })), timeline: [], runId: "", stopped: false }; }
  getSnapshot = () => this.snapshot;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  private emit() { this.listeners.forEach(listener => listener()); }
  private update(page: number, values: Partial<ReaderPage>) { this.snapshot = { ...this.snapshot, pages: this.snapshot.pages.map(p => p.page === page ? { ...p, ...values } : p) }; this.emit(); }
  private log(page: number, attempt: number, message: string) { this.snapshot = { ...this.snapshot, timeline: [...this.snapshot.timeline, { id: `${this.epoch}-${page}-${attempt}-${this.snapshot.timeline.length}`, at: new Date().toISOString(), page, attempt, message }].slice(-200) }; this.emit(); }
  enqueue(pages: number[], scenario = "valid", force = false) {
    this.snapshot = { ...this.snapshot, stopped: false, runId: this.snapshot.runId || `demo-run-${crypto.randomUUID()}` };
    for (const page of pages) { const current = this.snapshot.pages.find(p => p.page === page); if (!current || this.active.has(page) || this.queue.some(p => p.page === page) || !force && current.state !== "belum diminta") continue; this.queue.push({ page, scenario }); this.update(page, { state: "mengantre" }); }
    this.pump();
  }
  private pump() { while (!this.snapshot.stopped && this.active.size < 3 && this.queue.length) { const item = this.queue.shift()!; void this.load(item.page, item.scenario); } }
  private async load(page: number, scenario: string) {
    const abort = new AbortController(), epoch = this.epoch, current = this.snapshot.pages[page - 1], attempt = current.attempt + 1;
    this.active.set(page, abort);
    if (current.blobUrl) URL.revokeObjectURL(current.blobUrl);
    const url = ["403", "404", "413", "503", "504", "html", "corrupt"].includes(scenario) ? `/api/demo-reader/${scenario}` : `/demo-reader/reader-page-${page}.svg`;
    this.update(page, { state: "memuat", attempt, url, http: null, type: "", bytes: null, transfer: null, decode: null, width: null, height: null, blobUrl: "", message: "" }); this.log(page, attempt, `Memuat file lokal: ${scenario}.`);
    let blobUrl = "";
    try {
      if (scenario === "timeout") throw new Error("Timeout disimulasikan sebelum request; HTTP aktual belum tersedia.");
      const start = performance.now(), response = await fetch(url, { signal: abort.signal, cache: "no-store" });
      if (epoch !== this.epoch) return;
      this.update(page, { http: response.status, type: response.headers.get("Content-Type") ?? "" });
      if (!response.ok) throw new Error(`HTTP ${response.status} diterima dari fixture lokal.`);
      if (scenario === "body") throw new Error("Body gagal disimulasikan setelah header 200. Status HTTP tetap 200.");
      const blob = await response.blob();
      if (abort.signal.aborted || epoch !== this.epoch) return;
      this.update(page, { bytes: blob.size, transfer: performance.now() - start });
      if (!blob.type.startsWith("image/")) throw new Error(`Content-Type ${blob.type} bukan gambar.`);
      blobUrl = URL.createObjectURL(blob);
      const image = new Image(), decodeStart = performance.now(); image.src = blobUrl;
      await image.decode();
      if (abort.signal.aborted || epoch !== this.epoch) { URL.revokeObjectURL(blobUrl); return; }
      this.update(page, { state: "berhasil", decode: performance.now() - decodeStart, width: image.naturalWidth, height: image.naturalHeight, blobUrl, message: "HTTP, body dan decode file lokal selesai." }); this.log(page, attempt, "Berhasil untuk file lokal ini. Source/proxy produksi belum diuji.");
    } catch (error) {
      if (blobUrl) URL.revokeObjectURL(blobUrl);
      if (epoch !== this.epoch) return;
      const message = error instanceof Error ? error.message : "Attempt gagal.";
      this.update(page, { state: abort.signal.aborted ? "dibatalkan" : "gagal", message }); this.log(page, attempt, message);
    } finally { if (this.active.get(page) === abort) this.active.delete(page); if (epoch === this.epoch) this.pump(); }
  }
  stop() { this.snapshot = { ...this.snapshot, stopped: true }; this.queue = []; for (const abort of this.active.values()) abort.abort(); this.snapshot = { ...this.snapshot, pages: this.snapshot.pages.map(page => ["mengantre", "memuat"].includes(page.state) ? { ...page, state: "dibatalkan" as const, message: "Dibatalkan oleh pengguna." } : page) }; this.emit(); }
  reset() { this.stop(); this.epoch++; this.active.clear(); for (const page of this.snapshot.pages) if (page.blobUrl) URL.revokeObjectURL(page.blobUrl); this.snapshot = this.initial(); this.emit(); }
  dispose() { this.reset(); }
}
