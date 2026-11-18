import { tableFeatures as defineFeatures, columnFilteringFeature, globalFilteringFeature,
  rowSortingFeature, rowPaginationFeature, createFilteredRowModel, createSortedRowModel,
  createPaginatedRowModel, filterFn_includesString, sortFn_alphanumeric, sortFn_text } from "@tanstack/react-table";

export type TableColumnMeta={className?:string;rowHeader?:boolean};
// Shared headless pipeline: filter → sort → paginate.
export const tableFeatures=defineFeatures({
  columnMeta:{} as TableColumnMeta,
  columnFilteringFeature,globalFilteringFeature,rowSortingFeature,rowPaginationFeature,
  filterFns:{includesString:filterFn_includesString},sortFns:{alphanumeric:sortFn_alphanumeric,text:sortFn_text},
  filteredRowModel:createFilteredRowModel(),sortedRowModel:createSortedRowModel(),paginatedRowModel:createPaginatedRowModel(),
});
