import type { Fields, ResourceKind } from "./types";
export type FieldDefinition = { key: string; label: string; max?: number; required?: boolean; immutable?: boolean; type?: "textarea" | "date" | "url" | "number"; options?: string[] };
export const formFields: Partial<Record<ResourceKind, FieldDefinition[]>> = {
  comics: [
    { key: "title", label: "Judul", required: true, max: 500 }, { key: "slug", label: "Slug", required: true, immutable: true, max: 500 },
    { key: "source_name", label: "Source", required: true, immutable: true, options: ["komiku", "komiku_asia", "shinigami", "voratoon"] },
    { key: "status", label: "Status", options: ["ongoing", "completed", "hiatus"] }, { key: "alternate_title", label: "Judul alternatif", max: 500 },
    { key: "author", label: "Author", max: 300 }, { key: "artist", label: "Artist", max: 300 }, { key: "type", label: "Type", options: ["manga", "manhwa", "manhua"] },
    { key: "cover_url", label: "Cover URL HTTPS", type: "url", max: 2048 }, { key: "genre", label: "Genre editorial", max: 100 }, { key: "synopsis", label: "Sinopsis", type: "textarea", max: 20000 },
  ],
  chapters: [{ key: "comic_id", label: "Comic ID", immutable: true, required: true }, { key: "chapter_number", label: "Nomor chapter", immutable: true, required: true, type: "number" }, { key: "title", label: "Judul chapter", required: true, max: 500 }, { key: "release_date", label: "Tanggal rilis", type: "date" }, { key: "source_url", label: "Source URL HTTPS", immutable: true, type: "url", required: true, max: 2048 }],
  genres: [{ key: "title", label: "Nama genre", required: true, max: 100 }, { key: "slug", label: "Slug unik", required: true, immutable: true, max: 100 }],
  accounts: [{ key: "title", label: "Username", required: true, max: 100 }, { key: "display_name", label: "Nama tampilan", required: true, max: 100 }, { key: "status", label: "Status akun", options: ["active", "pending", "banned"] }],
  helpdesk: [{ key: "status", label: "Status penanganan", options: ["open", "in_progress", "resolved", "closed"] }, { key: "internal_note", label: "Catatan internal contoh", type: "textarea", max: 5000 }],
};
export function initialValues(kind: ResourceKind, parentId?: string): Fields {
  return Object.fromEntries((formFields[kind] ?? []).map(field => [field.key, field.key === "comic_id" ? parentId ?? "c1" : field.options?.[0] ?? ""]));
}
export function validateFields(kind: ResourceKind, values: Fields) {
  const errors: Fields = {};
  for (const field of formFields[kind] ?? []) {
    const value = values[field.key] ?? "";
    if (field.required && !value.trim()) errors[field.key] = `${field.label} wajib diisi.`;
    else if (field.max && value.length > field.max) errors[field.key] = `Maksimal ${field.max} karakter.`;
    else if (field.options && !field.options.includes(value)) errors[field.key] = "Pilih nilai yang tersedia.";
    else if (field.type === "number" && value && (!Number.isFinite(Number(value)) || Number(value) < 0)) errors[field.key] = "Gunakan nomor chapter nol atau positif; pecahan diperbolehkan.";
    else if (field.type === "url" && value) { try { const url = new URL(value); if (url.protocol !== "https:" || url.username || url.password) errors[field.key] = "Gunakan URL HTTPS tanpa credential."; } catch { errors[field.key] = "URL HTTPS tidak valid."; } }
    else if (field.type === "date" && value && !/^\d{4}-\d{2}-\d{2}$/.test(value)) errors[field.key] = "Gunakan tanggal yang valid.";
    if (field.key === "slug" && value && !/^[a-z0-9]+(?:[-_][a-z0-9]+)*$/.test(value)) errors[field.key] = "Gunakan huruf kecil, angka, tanda hubung atau underscore.";
  }
  return errors;
}
