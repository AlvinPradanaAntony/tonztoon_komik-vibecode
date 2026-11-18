import assert from 'node:assert/strict';
import { constructTable, tableFeatures as defineFeatures } from '@tanstack/react-table';
import { storeReactivityBindings } from '@tanstack/table-core/store-reactivity-bindings';
import { tableFeatures } from '../src/components/ui/table-model.ts';

const data=Array.from({length:15},(_,i)=>({id:String(i),name:`${i%2?'Odd':'Even'} group ${i}`,count:i*7%17}));
const table=constructTable({
  features:defineFeatures({...tableFeatures,coreReactivityFeature:storeReactivityBindings()}),
  data,columns:[{accessorKey:'id'},{accessorKey:'name'},{accessorKey:'count',filterFn:'includesString'}],
  getRowId:row=>row.id,globalFilterFn:'includesString',
  initialState:{pagination:{pageIndex:0,pageSize:5},sorting:[{id:'count',desc:true}]},
});
assert.equal(table.getRowModel().rows.length,5);
assert.equal(table.getRowModel().rows[0].original.count,16);
await new Promise(resolve=>setTimeout(resolve,0));
const firstPage=new Set(table.getRowModel().rows.map(r=>r.id));
table.nextPage();
assert.ok(table.getRowModel().rows.every(r=>!firstPage.has(r.id)));
table.lastPage();
assert.equal(table.getCanNextPage(),false);
table.setGlobalFilter('even');
table.getRowModel(); // Core models are lazy; React normally reads this during render.
await new Promise(resolve=>setTimeout(resolve,0));
assert.equal(table.getFilteredRowModel().rows.length,8);
assert.equal(table.atoms.pagination.get().pageIndex,0);
assert.equal(table.getPageCount(),2);
table.setColumnFilters([{id:'count',value:'1'}]);
assert.ok(table.getFilteredRowModel().rows.every(r=>r.original.name.startsWith('Even')&&String(r.original.count).includes('1')));
table.setGlobalFilter('no-such-record');
assert.equal(table.getRowModel().rows.length,0);
table.setGlobalFilter('');table.setColumnFilters([]);
table.setSorting([{id:'count',desc:false}]);table.setPageSize(10);
await new Promise(resolve=>setTimeout(resolve,0));
assert.equal(table.getRowModel().rows.length,10);
assert.equal(table.getRowModel().rows[0].original.count,0);
table.lastPage();
assert.equal(table.getRowModel().rows.length,5);
console.log('PASS: numeric sorting, global and column filters before pagination, page reset, empty results, page size and boundaries.');
