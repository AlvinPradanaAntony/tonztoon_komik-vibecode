// Historical, explicitly local fixtures from prototype/index.html. No transport.
export type Endpoint = { id: string; route: string; group: string; count: number; errors: number; p95: number };
export const endpoints: Endpoint[] = [
  { id: "reader", route: "/api/v1/sources/{source_name}/comics/{slug}/chapters/{chapter_number}", group: "Comics · Reader", count: 4820, errors: 42, p95: 2340 },
  { id: "images", route: "/api/v1/images/proxy", group: "Images", count: 8650, errors: 87, p95: 1640 },
  { id: "search", route: "/api/v1/search", group: "Search", count: 2760, errors: 8, p95: 486 },
  { id: "comics", route: "/api/v1/sources/{source_name}/comics", group: "Comics", count: 6230, errors: 4, p95: 218 },
  { id: "genres", route: "/api/v1/genres", group: "Genres", count: 1940, errors: 0, p95: 82 },
];
export const counts = [1164,1334,1213,1552,1455,1383,1649,1746,1625,2037,1819,1698,1989,1795,1941];
export const errors = [6,7,7,8,8,7,9,10,9,11,10,9,11,10,19];
export const number = (value: number, digits = 0) => value.toLocaleString("id-ID", { maximumFractionDigits: digits });
export type ViewState = "normal" | "loading" | "empty" | "error" | "stale" | "partial" | "denied" | "timeout" | "gap" | "down";
export const stateLabels: Record<ViewState,string> = { normal: "Data contoh", loading: "Memuat", empty: "Tanpa data", error: "Gagal memuat", stale: "Data stale", partial: "Cakupan parsial", denied: "Akses ditolak",timeout:"Timeout",gap:"Gap telemetry",down:"Backend down" };
export function snapshot(range: string) {
  const indices = range === "5" ? [10,11,12,13,14] : counts.map((_,i)=>i);
  // Longer windows aggregate repeated historical fixtures, never fabricate a live feed.
  const repeat = range === "60" ? 4 : range === "1440" ? 96 : 1;
  const buckets = indices.map(i=>({ time: `10:${27+i}`, count: counts[i]*repeat, errors: errors[i]*repeat }));
  return { buckets, count: buckets.reduce((s,b)=>s+b.count,0), errors: buckets.reduce((s,b)=>s+b.errors,0), repeat };
}
export function endpointSnapshot(range: string) {
  const data=snapshot(range);
  const allocate=(key:"count"|"errors",total:number)=>{
    let used=0;
    return endpoints.map((e,i)=>{const value=i===endpoints.length-1?total-used:Math.floor(e[key]/(key==="count"?24400:141)*total);used+=value;return value;});
  };
  const requests=allocate("count",data.count),failures=allocate("errors",data.errors);
  return endpoints.map((e,i)=>({...e,count:requests[i]/data.repeat,errors:failures[i]/data.repeat}));
}
