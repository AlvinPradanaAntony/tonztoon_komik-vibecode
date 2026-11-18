export type SchemaColumn = { name: string; type: string; constraints: string; nullable: string };
export type SchemaTable = { id: string; name: string; diagram: string; status: "existing" | "proposed"; columns: SchemaColumn[]; constraints: string[]; href?: string; permission?: string; source: string };
export type SchemaRelation = { id: string; source: string; target: string; label: string; kind: "FK terdefinisi" | "Relasi logis" | "Usulan migration" };
function table(id: string, diagram: string, status: SchemaTable["status"], fields: string[], constraints: string[] = [], href?: string, permission?: string): SchemaTable {
  return { id, name: id, diagram, status, columns: fields.map(field => { const [name, type, keys = "", nullable = "Belum diverifikasi"] = field.split(":"); return { name, type, constraints: keys, nullable }; }), constraints, href, permission, source: status === "existing" ? "Subset model SQLAlchemy, contrat PRD §17" : "Rancangan PRD §17, bukan bukti migration terpasang" };
}
export const schemaTables: SchemaTable[] = [
  table("comics", "catalog", "existing", ["id:integer:PK:Tidak", "source_name:varchar(100):unique(source_name,slug):Tidak", "slug:varchar(600):unique(source_name,slug):Tidak", "title:varchar(500)::Tidak", "updated_at:timestamptz::Ya"], ["UNIQUE (source_name, slug)"], "/data/comics", "data:read"),
  table("chapters", "catalog", "existing", ["id:integer:PK:Tidak", "comic_id:integer:FK comics.id:Tidak", "chapter_number:float:unique(comic_id,chapter_number):Tidak", "title:varchar(500)::Ya", "images:jsonb:array, bukan tabel images:Ya", "images_are_invalid:boolean:generated, baca saja:Tidak"], ["UNIQUE (comic_id, chapter_number)"], "/data/comics/c1/chapters", "data:read"),
  table("genres", "catalog", "existing", ["id:integer:PK:Tidak", "name:varchar(100):UNIQUE:Tidak", "slug:varchar(120):UNIQUE:Tidak"], [], "/data/genres", "data:read"),
  table("comic_genre", "catalog", "existing", ["comic_id:integer:PK FK comics.id:Tidak", "genre_id:integer:PK FK genres.id:Tidak"]),
  table("user_bookmarks", "catalog", "existing", ["id:integer:PK:Tidak", "user_id:uuid:relasi logis, bukan FK:Tidak", "comic_id:integer:FK comics.id:Tidak"], ["UNIQUE (user_id, comic_id)"]),
  table("user_progress", "catalog", "existing", ["id:integer:PK:Tidak", "user_id:uuid:relasi logis, bukan FK:Tidak", "comic_id:integer:FK comics.id:Tidak", "chapter_id:integer:FK chapters.id:Tidak"], ["UNIQUE (user_id, comic_id)"]),
  table("user_collections", "catalog", "existing", ["id:integer:PK:Tidak", "user_id:uuid:relasi logis, bukan FK:Tidak", "normalized_name:string::Tidak"]),
  table("user_collection_comics", "catalog", "existing", ["id:integer:PK:Tidak", "collection_id:integer:FK user_collections.id:Tidak", "comic_id:integer:FK comics.id:Tidak"], ["UNIQUE (collection_id, comic_id)"]),
  table("profiles", "users", "existing", ["id:uuid:PK:Tidak", "username:varchar(50)::Ya", "normalized_username:varchar(50):UNIQUE:Ya", "display_name:varchar(120)::Ya"], ["Supabase Auth: relasi identitas logis tanpa FK pada model Profile"], "/data/accounts", "users:manage"),
  table("helpdesk_submissions", "users", "existing", ["id:uuid:PK:Tidak", "user_id:uuid:FK profiles.id:Ya", "reference_code:string:UNIQUE:Tidak", "category:string::Tidak", "status:string::Tidak"], [], "/data/helpdesk", "helpdesk:manage"),
  table("user_push_devices", "users", "existing", ["id:uuid:PK:Tidak", "user_id:uuid:FK profiles.id:Tidak", "platform:string::Tidak"]),
  table("environments", "monitoring", "proposed", ["id:uuid:PK", "key:string:UNIQUE"]),
  table("api_endpoints", "monitoring", "proposed", ["id:uuid:PK", "environment_id:uuid:FK environments.id", "method:string", "route_template:string"], ["UNIQUE (environment_id, method, route_template)"]),
  table("metric_buckets", "monitoring", "proposed", ["id:uuid:PK", "endpoint_id:uuid:FK api_endpoints.id", "bucket_start:datetime", "bucket_width:integer", "completed_count:bigint", "duration_histogram:jsonb"], ["UNIQUE (endpoint_id, bucket_start, bucket_width)"]),
  table("request_logs", "monitoring", "proposed", ["observation_id:uuid:PK", "endpoint_id:uuid:FK api_endpoints.id", "request_id:string:correlation key, bukan PK", "instance_id:string", "observed_at:datetime", "outcome:string"]),
  table("health_probes", "monitoring", "proposed", ["id:uuid:PK", "environment_id:uuid:FK environments.id", "scheduled_at:datetime", "result:string"]),
  table("runtime_log_events", "monitoring", "proposed", ["id:uuid:PK", "environment_id:uuid:FK environments.id", "instance_id:string", "source:string", "logger_name:string", "level:string", "request_id:string:opsional", "occurred_at:datetime", "received_at:datetime", "redacted_message:string", "sanitized_stack:jsonb"]),
  table("alert_rules", "monitoring", "proposed", ["id:uuid:PK", "environment_id:uuid:FK environments.id", "key:string", "thresholds:jsonb"]),
  table("alert_incidents", "monitoring", "proposed", ["id:uuid:PK", "rule_id:uuid:FK alert_rules.id", "scope_key:string", "state:string", "started_at:datetime"]),
  table("comics", "admin", "existing", ["id:integer:PK:Tidak"]), table("chapters", "admin", "existing", ["id:integer:PK:Tidak"]),
  table("comic_admin_overrides", "admin", "proposed", ["comic_id:integer:PK FK comics.id", "allowed_patch:jsonb:allowlist wajib", "archived_at:datetime", "revision:integer", "updated_by:uuid:relasi logis"]),
  table("chapter_admin_overrides", "admin", "proposed", ["chapter_id:integer:PK FK chapters.id", "allowed_patch:jsonb:allowlist wajib", "archived_at:datetime", "revision:integer", "updated_by:uuid:relasi logis"]),
  table("admin_operations", "admin", "proposed", ["id:uuid:PK", "idempotency_key:string", "request_fingerprint:string", "state:string"], ["Idempotency scoped aktor + environment + operasi; minimal 24 jam"]),
  table("admin_audit_events", "admin", "proposed", ["id:uuid:PK", "operation_id:uuid:FK admin_operations.id", "actor_user_id:uuid:relasi logis", "resource_type:string:polymorphic", "resource_id:string:bukan FK bebas", "redacted_diff:jsonb"], ["Retensi rancangan 90 hari"], "/data/audit", "audit:read"),
  table("admin_outbox_events", "admin", "proposed", ["id:uuid:PK", "audit_event_id:uuid:FK admin_audit_events.id", "type:string", "delivered_at:datetime"], ["Retensi rancangan 7 hari"]),
  table("admin_sessions", "admin", "proposed", ["id:uuid:PK", "user_id:uuid:relasi logis", "encrypted_tokens:string:server only, bukan data row", "expires_at:datetime"]),
];
const relation = (source: string, target: string, kind: SchemaRelation["kind"] = "FK terdefinisi"): SchemaRelation => ({ id: `${source}-${target}`, source, target, kind, label: `${source} → ${target}` });
export const schemaRelations = [relation("comics", "chapters"), relation("comics", "comic_genre"), relation("genres", "comic_genre"), relation("comics", "user_bookmarks"), relation("comics", "user_progress"), relation("chapters", "user_progress"), relation("comics", "user_collection_comics"), relation("user_collections", "user_collection_comics"), relation("profiles", "helpdesk_submissions"), relation("profiles", "user_push_devices"), relation("profiles", "user_bookmarks", "Relasi logis"), ...[["environments", "api_endpoints"], ["api_endpoints", "metric_buckets"], ["api_endpoints", "request_logs"], ["environments", "health_probes"], ["environments", "runtime_log_events"], ["environments", "alert_rules"], ["alert_rules", "alert_incidents"], ["comics", "comic_admin_overrides"], ["chapters", "chapter_admin_overrides"], ["admin_operations", "admin_audit_events"], ["admin_audit_events", "admin_outbox_events"]].map(([source, target]) => relation(source, target, "Usulan migration"))];
export const diagramLabels = { catalog: "A · Katalog / library", users: "B · Profil / pengguna", monitoring: "C · Monitoring (rancangan)", admin: "D · Editorial / audit / sesi (rancangan)" };
export type FlowNode = { id: string; label: string; domain: string; x: number; y: number; status: string; description: string; href?: string };
export const flowNodes: FlowNode[] = [
  { id: "reader", label: "Flutter / client REST", domain: "business", x: 20, y: 40, status: "Existing", description: "Pembaca katalog dan chapter" },
  { id: "admin", label: "Browser admin", domain: "admin", x: 20, y: 260, status: "Frontend contoh", description: "Preview, validasi dan draft", href: "/overview" },
  { id: "bff", label: "Next.js BFF", domain: "admin", x: 330, y: 260, status: "Integrasi fase 3", description: "Sesi server dan relay berizin" },
  { id: "api", label: "FastAPI", domain: "business", x: 640, y: 40, status: "Source existing", description: "API bisnis dan admin berfitur flag", href: "/endpoints" },
  { id: "db", label: "PostgreSQL bisnis", domain: "business", x: 950, y: 40, status: "Existing, DB belum diperiksa", description: "Katalog, chapter, profil, library" },
  { id: "auth", label: "Supabase Auth / Storage", domain: "business", x: 1260, y: 40, status: "Belum diukur", description: "Identitas, cover dan avatar" },
  { id: "sources", label: "Source komik eksternal", domain: "business", x: 20, y: 480, status: "Belum diukur", description: "Metadata, chapter dan bytes gambar", href: "/data/sources" },
  { id: "scraper", label: "Scraper / GitHub Actions", domain: "business", x: 330, y: 480, status: "Source existing", description: "Upsert metadata scraper, bukan health live" },
  { id: "editorial", label: "Override / audit / outbox", domain: "admin", x: 950, y: 260, status: "Source ada, integrasi belum diuji", description: "Transaksi, versi dan operasi admin", href: "/data/audit" },
  { id: "collector", label: "Collector runtime / ASGI", domain: "telemetry", x: 640, y: 480, status: "Belum terhubung", description: "Redaksi sebelum buffer dan penyimpanan", href: "/runtime-logs" },
  { id: "monitor", label: "Penyimpanan monitoring", domain: "telemetry", x: 950, y: 480, status: "DB belum diverifikasi", description: "Agregat, log, probe dan insiden" },
  { id: "worker", label: "Worker probe / alert", domain: "telemetry", x: 1260, y: 480, status: "Belum terhubung", description: "Proses independen dari API dan browser", href: "/health" },
];
export const flowEdges = [
  ["reader", "api", "Request bisnis"], ["admin", "bff", "Submit dengan If-Match"], ["bff", "api", "Bearer dan izin modul"], ["api", "db", "Query / nilai efektif"], ["api", "auth", "Identitas / media"], ["sources", "scraper", "Metadata / chapter"], ["scraper", "db", "Upsert metadata source"], ["api", "sources", "Lazy fetch / proxy"], ["api", "editorial", "Mutation / audit / commit"], ["editorial", "bff", "Outbox / refresh"], ["api", "collector", "Telemetry tersanitasi"], ["collector", "monitor", "Buffer / flush"], ["worker", "monitor", "Probe / evaluasi"], ["monitor", "bff", "Snapshot / histori"],
].map(([source, target, label], index) => ({ id: `edge-${index}`, source, target, label, measured: false }));
