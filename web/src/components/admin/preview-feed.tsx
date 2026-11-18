"use client";
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { Badge, Button, EmptyState, Select } from "@/components/ui";
import { effective, type Fields } from "@/lib/admin-data/types";
import { useWorkspace } from "@/lib/admin-data/demo-repository";
import { useQueryState } from "./demo-boundary";
import { textLink } from "@/components/ui/styles";
export function PreviewFeed({ comics, returnTo }: { comics: (Fields & {id:string})[]; returnTo:string }) {
  const {params,set,href}=useQueryState(),workspace=useWorkspace();
  const size=[4,8,20].includes(Number(params.get('size')))?Number(params.get('size')):4;
  const pages=Math.max(1,Math.ceil(comics.length/size)),requested=Number(params.get('page')??1),page=Math.min(pages,Math.max(1,Number.isFinite(requested)?Math.floor(requested):1));
  if(!comics.length)return <EmptyState title="Tidak ada komik yang cocok" description="Coba query atau source lain." action={<Button onClick={()=>set({q:null,source:null,page:null})}>Reset pencarian</Button>}/>;
  return <>
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{comics.slice((page-1)*size,page*size).map(comic=>{
      const target=href(`/comic-preview/${comic.source_name}/${comic.slug}`,{feedReturn:returnTo,q:null,page:null,sort:null,order:null});
      const chapterRecords=workspace.records.filter(record=>record.kind==='chapters'&&record.parentId===comic.id&&!record.archived);
      const chapters=chapterRecords.length,latest=[...chapterRecords].sort((a,b)=>Number(effective(b).chapter_number)-Number(effective(a).chapter_number))[0];
      return <article className="card min-w-0 rounded-inner border border-line bg-surface p-4" key={comic.id}>
        <div className="mb-4 grid h-40 place-content-center rounded-control bg-panel p-4 text-center text-xs/5 text-muted"><span>Cover placeholder</span><span>Data contoh</span></div>
        <Badge className="mb-3 w-fit">{comic.source_name}</Badge>
        <h2 className="text-base/6 font-semibold wrap-anywhere"><Link className={textLink} href={target}>{comic.title}</Link></h2>
        <p className="my-3 text-xs/5 text-muted">{chapters} chapter aktif · {comic.genre||'Genre belum tersedia'}</p>
        <p className="mb-3 text-xs/5 text-muted">Chapter terbaru: {latest?effective(latest).chapter_number:'Belum tersedia'}</p>
        <Link className={`${textLink} mt-auto`} href={target}>Periksa komik</Link>
      </article>;
    })}</div>
    <nav className="mt-5 flex flex-wrap items-center gap-3 text-sm" aria-label="Pagination feed preview"><p className="me-auto" role="status">{(page-1)*size+1} sampai {Math.min(page*size,comics.length)} dari {comics.length} komik contoh</p><Select label="Item per halaman" value={size} onChange={event=>set({size:event.target.value,page:null})}>{[4,8,20].map(value=><option key={value}>{value}</option>)}</Select><Button disabled={page<=1} onClick={()=>set({page:String(page-1)})}>Sebelumnya</Button><Button disabled={page>=pages} onClick={()=>set({page:String(page+1)})}>Berikutnya</Button></nav>
    <p className="mt-3 text-xs/5 text-muted">Urutan mengikuti feed fixture yang dipilih. Tidak diganti dengan sort judul client.</p>
  </>;
}
