"use client";
import { Table, type TableColumn } from "@/components/ui";
import { useQueryState } from "./demo-boundary";
import { adminTable } from "./patterns";
export function UrlTable<T extends { id: string }>({ data, columns, caption, defaultSort = "title", pageSize = 50 }: { data: T[]; columns: TableColumn<T>[]; caption: string; defaultSort?: string; pageSize?: number }) {
  const { params, set } = useQueryState();
  const size = [5, 10, 25, 50, 100].includes(Number(params.get("size"))) ? Number(params.get("size")) : pageSize;
  const rawPage = Number(params.get("page") ?? 1);
  const page = Math.min(Math.max(0, Number.isFinite(rawPage) ? Math.floor(rawPage) - 1 : 0), Math.max(0, Math.ceil(data.length / size) - 1));
  const allowedSorts = columns.map(column => "accessorKey" in column ? String(column.accessorKey) : column.id);
  const sort = allowedSorts.includes(params.get("sort") ?? "") ? params.get("sort")! : defaultSort;
  const sorting = sort ? [{ id: sort, desc: params.get("order") === "desc" }] : [];
  const pagination = { pageIndex: page, pageSize: size };
  return <Table className={adminTable} caption={caption} data={data} columns={columns} getRowId={row => row.id} pageSize={pageSize} sorting={sorting} onSortingChange={update => {
    const first = (typeof update === "function" ? update(sorting) : update)[0];
    set({ sort: first?.id ?? null, order: first?.desc ? "desc" : "asc", page: null });
  }} paginationState={pagination} onPaginationChange={update => {
    const next = typeof update === "function" ? update(pagination) : update;
    set({ page: String(next.pageSize !== size ? 1 : next.pageIndex + 1), size: String(next.pageSize) });
  }} emptyState={{ title: "Tidak ada hasil yang cocok", action: <button className="min-h-11 cursor-pointer underline" onClick={() => set(Object.fromEntries(['q','status','source','genre','relation','category','result','actor','action','request_id','endpoint','group','method','outcome','duration','from','to','level','logger','kind','instance','page'].map(key=>[key,null])))}>Reset filter</button> }} />;
}
