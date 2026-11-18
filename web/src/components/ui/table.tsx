"use client";
import { useState, type ComponentProps, type ReactNode } from "react";
import { useTable, type ColumnDef, type ColumnFiltersState, type SortingState, type PaginationState, type OnChangeFn, type RowData } from "@tanstack/react-table";
import { tableFeatures } from "./table-model";
import { Button } from "./button";
import { Select } from "./select";
import { ScrollArea } from "./scroll-area";
import { Spinner } from "./spinner";
import { EmptyState, type EmptyStateProps } from "./empty-state";
import { cx, type UiSize } from "./types";
import { focus, fieldError } from "./styles";

export type TableColumn<T extends RowData> = ColumnDef<typeof tableFeatures, T>;
export type TableState = "ready" | "loading" | "empty" | "error";
export type TableSummary = { filteredRows:number; totalRows:number };
export type TableProps<T extends RowData> = Omit<ComponentProps<"table">,"children"> & {
  data:T[]; columns:TableColumn<T>[]; caption:string; captionHidden?:boolean;
  state?:TableState; message?:ReactNode; size?:UiSize; onRetry?:()=>void;
  globalFilter?:string; columnFilters?:ColumnFiltersState;
  sorting?:SortingState; onSortingChange?:OnChangeFn<SortingState>; initialSorting?:SortingState;
  pagination?:boolean; pageSize?:number; getRowId?:(row:T)=>string;
  paginationState?:PaginationState; onPaginationChange?:OnChangeFn<PaginationState>;
  emptyState?: Omit<EmptyStateProps,"announce">;
  footer?:(summary:TableSummary)=>ReactNode;
};
const sizes={sm:'table-sm',md:'table-md',lg:'table-lg'};
const noFilters:ColumnFiltersState=[];
const noSorting:SortingState=[];

export function Table<T extends RowData>({data,columns,caption,captionHidden=false,state='ready',message,size='md',onRetry,
  globalFilter='',columnFilters=noFilters,sorting,onSortingChange,initialSorting=noSorting,pagination=true,
  pageSize=10,getRowId,footer,emptyState,className,paginationState,onPaginationChange,...props}:TableProps<T>) {
  const [localSorting,setLocalSorting]=useState<SortingState>(initialSorting);
  const table=useTable({features:tableFeatures,data,columns,getRowId,
    state:{globalFilter,columnFilters,sorting:sorting??localSorting,...(paginationState?{pagination:paginationState}:{})},onSortingChange:onSortingChange??setLocalSorting,
    ...(onPaginationChange?{onPaginationChange,autoResetPageIndex:false}:{}),
    initialState:{pagination:{pageIndex:0,pageSize}},globalFilterFn:'includesString',manualPagination:!pagination});
  const count=table.getFilteredRowModel().rows.length;
  const effectiveState=state==='ready'&&!count?'empty':state;
  const page=table.state.pagination;
  const filtered=!!globalFilter.trim()||columnFilters.length>0;
  return <div className="tt-data-table" aria-busy={state==='loading'||undefined}>
    <ScrollArea label={`Tabel: ${caption}`} className="max-w-full overflow-auto rounded-control" axis="both">
      <table {...props} data-size={size} className={cx('table tt-table text-sm [&_:is(th,td)]:border-line [&_:is(th,td)]:px-2 [&_:is(th,td)]:whitespace-normal [&_:is(th,td)]:wrap-anywhere [&_th]:font-medium [&_thead_th]:text-muted [&_tbody_th]:text-foreground',size==='sm'?'[&_:is(th,td)]:py-2':size==='lg'?'[&_:is(th,td)]:py-4':'[&_:is(th,td)]:py-3',sizes[size],className)}>
        <caption className={captionHidden?'sr-only':'pb-3 text-start text-sm text-muted'}>{caption}</caption>
        <thead>{table.getHeaderGroups().map(group=><tr key={group.id}>{group.headers.map(header=>{
          const col=header.column,meta=col.columnDef.meta,sorted=col.getIsSorted();
          return <th key={header.id} scope="col" colSpan={header.colSpan} className={meta?.className}
            aria-sort={col.getCanSort()?(sorted==='asc'?'ascending':sorted==='desc'?'descending':'none'):undefined}>
            {header.isPlaceholder?null:col.getCanSort()?<button type="button" className={cx("tt-table-sort inline-flex min-h-11 cursor-pointer items-center gap-2 text-[inherit] [font:inherit]",focus)} onClick={col.getToggleSortingHandler()}>
              <table.FlexRender header={header}/><span className="text-muted" aria-hidden="true">{sorted==='asc'?'↑':sorted==='desc'?'↓':'↕'}</span>
            </button>:<table.FlexRender header={header}/>}</th>;
        })}</tr>)}</thead>
        <tbody>{effectiveState==='ready'?table.getRowModel().rows.map(row=><tr key={row.id}>{row.getAllCells().map(cell=>{
          const meta=cell.column.columnDef.meta,Cell=meta?.rowHeader?'th':'td';
          return <Cell key={cell.id} scope={meta?.rowHeader?'row':undefined} className={meta?.className}><table.FlexRender cell={cell}/></Cell>;
        })}</tr>):effectiveState==='empty'?<tr><td className="h-0 border-0 p-0!" colSpan={table.getAllLeafColumns().length}><span className="sr-only">Tidak ada baris data.</span></td></tr>:<tr><td colSpan={table.getAllLeafColumns().length}><div className={cx('flex flex-wrap items-center gap-3 py-4',effectiveState==='error'&&fieldError)} role="status">
          {effectiveState==='loading'&&<Spinner decorative/>}<p>{message??({loading:'Memuat data.',empty:'Belum ada data untuk ditampilkan.',error:'Data gagal dimuat.'}[effectiveState])}</p>
          {effectiveState==='error'&&onRetry&&<Button size="sm" onClick={onRetry}>Coba lagi</Button>}
        </div></td></tr>}</tbody>
      </table>
    </ScrollArea>
    {effectiveState==='empty'&&<EmptyState announce size="sm" title={filtered?'Tidak ada hasil pencarian':'Belum ada data'}
      icon={filtered?'search':'requests'} description={message??(filtered?'Coba kata kunci lain atau sesuaikan filter yang dipilih.':'Data akan tampil di sini setelah tersedia.')} {...emptyState}/>}
    {effectiveState==='ready'&&pagination&&<nav className="flex flex-wrap items-center gap-2 py-4 text-[13px]" aria-label={`Pagination: ${caption}`}>
      <p className="me-auto" role="status">{page.pageIndex*page.pageSize+1}–{Math.min((page.pageIndex+1)*page.pageSize,count)} dari {count} baris</p>
      <Select fieldClassName="flex items-center gap-2" label="Baris per halaman" value={page.pageSize} onChange={e=>table.setPageSize(Number(e.target.value))}>
        {Array.from(new Set([pageSize,page.pageSize,10,25,50,100])).sort((a,b)=>a-b).map(n=><option key={n} value={n}>{n}</option>)}
      </Select>
      <Button appearance="outline" disabled={!table.getCanPreviousPage()} onClick={()=>table.firstPage()} aria-label="Halaman pertama">«</Button>
      <Button appearance="outline" disabled={!table.getCanPreviousPage()} onClick={()=>table.previousPage()}>Sebelumnya</Button>
      <span>Halaman {page.pageIndex+1} dari {table.getPageCount()}</span>
      <Button appearance="outline" disabled={!table.getCanNextPage()} onClick={()=>table.nextPage()}>Berikutnya</Button>
      <Button appearance="outline" disabled={!table.getCanNextPage()} onClick={()=>table.lastPage()} aria-label="Halaman terakhir">»</Button>
    </nav>}
    {footer?.({filteredRows:count,totalRows:data.length})}
  </div>;
}
