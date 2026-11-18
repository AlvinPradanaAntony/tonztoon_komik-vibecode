import type { DemoRecord, Fields, ResourceKind, Workspace } from "@/lib/admin-data/types";
export const sourceRegistry = [
  { id: "komiku", title: "Komiku", status: "active" }, { id: "komiku_asia", title: "Komiku Asia", status: "active" },
  { id: "shinigami", title: "Shinigami", status: "active" }, { id: "voratoon", title: "Voratoon", status: "active" }, { id: "kiryuu", title: "Kiryuu", status: "backup" },
];
export const chapterNumbers = [1, 2, 3, 10, 11, 12, 12.5, 13];
const record = (kind: ResourceKind, id: string, source: Fields, parentId?: string, archived = false): DemoRecord => ({ kind, id, source, override: {}, revision: 1, archived, parentId });
export function createWorkspace(): Workspace {
  const comics = Array.from({ length: 8 }, (_, i) => record("comics", `c${i + 1}`, {
    title: `Komik Contoh ${String.fromCharCode(65 + i)}`, slug: `komik-contoh-${String.fromCharCode(97 + i)}`,
    source_name: ["komiku", "shinigami", "voratoon", "komiku_asia"][i % 4], status: ["ongoing", "completed", "ongoing", "hiatus"][i % 4],
    genre: ["Action", "Fantasy", "Adventure"][i % 3], synopsis: "Sinopsis contoh untuk pemeriksaan editorial.", alternate_title: "", author: "", artist: "", type: "manga", cover_url: "", rating: "Belum tersedia", total_views: "Belum tersedia",
  }, undefined, i === 4));
  const chapters = comics.flatMap(comic => chapterNumbers.map(number => record("chapters", `${comic.id}-${number}`, {
    title: `Chapter ${number}`, chapter_number: String(number), comic_id: comic.id, release_date: "2026-10-24", source_url: `https://example.test/${comic.id}/chapter-${number}`, total_images: "3", images_are_invalid: "false",
  }, comic.id, number === 3)));
  const genres = ["Action", "Fantasy", "Adventure"].map((title, i) => record("genres", `g${i + 1}`, { title, slug: title.toLowerCase() }));
  const sources = sourceRegistry.map(source => record("sources", source.id, { title: source.title, source_name: source.id, status: source.status, observed_at: "24 Okt 2026, 10:42 UTC+7 (contoh)", upstream_health: "Belum dipantau" }));
  const accounts = Array.from({ length: 7 }, (_, i) => record("accounts", `u${i + 1}`, { title: `reader_contoh_0${i + 1}`, display_name: `Reader Contoh ${i + 1}`, email_masked: `r***${i + 1}@example.test`, status: i === 3 ? "banned" : i === 5 ? "pending" : "active", role: "reader" }));
  const helpdesk = ["Reader tidak memuat satu halaman", "Ulasan contoh antarmuka", "Chapter pecahan sulit ditemukan", "Cover tidak tampil", "Review contoh tanpa PII", "Pencarian kosong"].map((title, i) => record("helpdesk", `HD-DEMO-00${i + 1}`, { title, category: i % 3 === 1 ? "review" : "report", status: ["open", "resolved", "in_progress", "open", "closed", "open"][i], message: "Contoh laporan tersanitasi, tanpa data pribadi.", internal_note: "", platform: "Android / versi contoh" }));
  const audit = Array.from({ length: 6 }, (_, i) => record("audit", `audit-00${i + 1}`, { title: `Tindakan contoh ${i + 1}`, actor: i === 2 ? "operator-contoh" : "admin-contoh", resource: ["comics:c1", "comics:c5", "helpdesk:HD-DEMO-002", "chapters:c1-12.5", "accounts:u1", "genres:g1"][i], action: ["update", "archive", "status", "update", "profile", "update"][i], result: ["success", "success", "success", "conflict", "pending", "success"][i], request_id: `demo-req-000${i + 5}`, operation_id: `demo-op-00${i + 1}`, permission: i === 4 ? "users:manage" : i === 2 ? "helpdesk:manage" : "catalog:write", observed_at: `2026-10-24T03:${String(40 - i * 5).padStart(2, "0")}:00Z`, before: i === 0 ? "Komik Contoh A" : "", after: i === 0 ? "Komik Contoh A (editorial)" : "" }));
  return { records: [...comics, ...chapters, ...genres, ...sources, ...accounts, ...helpdesk, ...audit], operations: [], profile: "all", revision: 1 };
}
