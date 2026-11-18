"use client";
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useMemo, useState } from "react";
import type { SortingState } from "@tanstack/react-table";
import { Alert, Badge, Button, Dialog, EmptyState, Icon, Input, Panel, Select, Table, Tabs, type TableColumn } from "@/components/ui";
import { number, stateLabels, type ViewState } from "@/lib/demo/monitoring";
import { advance, createSimulation, demoTime, scenarios, summarize, type Scenario } from "@/lib/demo/overview-simulation";
import { PageTitle, detailList, numberCell, tableToolbar, adminTable, disclosure, hiddenLabel, panelHeader } from "./patterns";
import { textLink } from "@/components/ui/styles";
import { cx } from "@/components/ui/types";
import { useSimulation } from "@/lib/monitoring/demo-store";
import { DemoBoundary } from "./demo-boundary";
import { useWorkspace } from "@/lib/admin-data/demo-repository";
import { profiles } from "@/lib/admin-data/types";
import { monitoringWindow, periodDate } from "@/lib/monitoring/window";
import { CustomRange } from './custom-range';

type OverviewEndpoint=ReturnType<typeof summarize>['endpoints'][number];
const value=(n:number|null,suffix='')=>n===null?'Belum tersedia':`${number(n,2)}${suffix}`;
const bucketColumns:TableColumn<ReturnType<typeof summarize>['buckets'][number]>[]=[
  {accessorKey:'at',header:'Waktu UTC+7',cell:({row})=>demoTime(row.original.at),meta:{rowHeader:true}},
  {accessorKey:'count',header:'Request',meta:{className:numberCell}},
  {accessorKey:'errors',header:'5xx',meta:{className:numberCell}},
  {accessorKey:'p95',header:'p95 ms',cell:({row})=>value(row.original.p95),meta:{className:numberCell}},
];
function endpointColumns(open:(id:string)=>void):TableColumn<OverviewEndpoint>[] {return [
  {id:'route',accessorFn:e=>`${e.route} ${e.group}`,header:'Method / route',meta:{rowHeader:true},cell:({row:{original:e}})=><><Button variant="ghost" className="h-auto items-start justify-start px-0 py-2 text-start font-medium whitespace-normal [&>span]:shrink-0 [&>span]:rounded-full [&>span]:bg-accent-bg [&>span]:px-2 [&>span]:py-1 [&>span]:text-[11px] [&>span]:text-accent [&>code]:max-w-91.25 [&>code]:text-xs/relaxed [&>code]:font-normal [&>code]:wrap-anywhere" onClick={()=>open(e.id)}><span>GET</span><code>{e.route}</code></Button><small className="ms-12 block text-muted">{e.group==='Images'?'Images · Streaming':e.group==='Comics'?'Comics · Katalog':e.group}</small></>},
  {accessorKey:'count',header:'Request',meta:{className:numberCell},cell:({row})=>number(row.original.count)},
  {accessorKey:'errors',header:'5xx',meta:{className:numberCell},cell:({row:{original:e}})=><>{e.count?`${number(e.errors/e.count*100,2)}%`:'Belum tersedia'}<small>{e.errors} respons</small></>},
  {accessorKey:'p95',header:'p95',meta:{className:numberCell},cell:({row})=>value(row.original.p95,' ms')},
  {id:'condition',header:'Kondisi',enableSorting:false,cell:({row:{original:e}})=><Badge tone={e.p95&&e.p95>2000?'warning':'neutral'}>{!e.count?'Belum ada trafik':e.p95&&e.p95>2000?'Latensi tinggi':'Dalam ambang'}</Badge>},
  {id:'detail',header:()=><span className="sr-only">Detail endpoint</span>,enableSorting:false,cell:({row})=><Button variant="ghost" className="w-11 p-0" aria-label={`Detail ${row.original.route}`} onClick={()=>open(row.original.id)}><Icon name="chevron"/></Button>},
];}

export function Overview() {
  const params=useSearchParams(),router=useRouter(),path=usePathname();
  const range=params.get('range')==='custom'?'custom':["5","15","60","1440"].includes(params.get('range')??'')?params.get('range')!:'15';
  const env=(params.get('environment')??params.get('env'))==='staging'?'staging':'production';
  const metric=['traffic','latency','status'].includes(params.get('chart')??params.get('metric')??'')?(params.get('chart')??params.get('metric'))!:'traffic';
  const query=params.get('q')??'',sort=params.get('sort')??'priority';
  const state=(Object.keys(stateLabels).includes(params.get('state')??'')?params.get('state'):'normal') as ViewState;
  function set(key:string,value:string){const next=new URLSearchParams(params);next.set(key,value);router.replace(`${path}?${next}`,{scroll:false});}
  const [sim,setSim]=useSimulation();const [scenario,setScenario]=useState<Scenario>('healthy');const [demoEnv,setDemoEnv]=useState('production');
  const [detail,setDetail]=useState<string|null>(null);
  const window=monitoringWindow(params,sim.now);
  const data=useMemo(()=>summarize({...sim,now:window.end},env,window.minutes),[sim,env,window.end,window.minutes]);
  const coverageLabel=data.scheduledProbes?`${number(data.coverage,2)}%`:'Belum tersedia';
  const columns=useMemo(()=>endpointColumns(setDetail),[setDetail]);
  const direction=params.get('order')??(sort==='name'?'asc':'desc');
  const sorting=useMemo<SortingState>(()=>sort==='none'?[]:[{id:sort==='name'?'route':sort==='count'?'count':sort==='errors'?'errors':'p95',desc:direction==='desc'}],[sort,direction]);
  const activeScenario=state==='gap'?'gap':sim.environment===env&&window.end===sim.now?sim.scenario:'healthy';
  const latestProbes=sim.probes.filter(probe=>probe.environment===env&&probe.at<=window.end).slice(-2);
  const service=['stale','gap'].includes(state)||!latestProbes.length||latestProbes.some(probe=>!probe.known)||latestProbes.at(-1)!.at<window.end-10000?'Belum tersedia':latestProbes.every(probe=>!probe.ok)?'Tidak terjangkau':'Terjangkau';
  const hidden=['loading','empty','error','denied','timeout','down'].includes(state)||!data.count||!!window.error;
  const partialWindow=window.start<(sim.events[0]?.at??sim.now)||sim.dropped>0||sim.lost>0;
  const endpoint=data.endpoints.find(e=>e.id===detail);
  const context=new URLSearchParams({env,range,...(range==='custom'?{window_from:params.get('window_from')??'',window_to:params.get('window_to')??''}:{})}).toString();
  function chart(kind:string){
    if(kind==='status')return <div className="p-4"><Table caption="Seluruh kelas status HTTP pada snapshot yang sama" pagination={false} data={data.statuses} columns={[{accessorKey:'code',header:'Kelas HTTP',cell:({row})=>`${row.original.code/100}xx`},{accessorKey:'count',header:'Respons',meta:{className:numberCell}},{id:'rate',header:'Persentase',meta:{className:numberCell},cell:({row})=>data.count?`${number(row.original.count/data.count*100,2)}%`:'Belum tersedia'}]}/></div>;
    const last=data.buckets.length-1;
    const max=Math.max(1,...data.buckets.map(b=>kind==='latency'?(b.p95??0):kind==='status'?b.errors:b.count));
    const top=Math.max(4,Math.ceil(max/4)*4);
    return <div className="mx-4 mt-3 overflow-auto max-sm:mx-1.5 [&_text]:fill-muted [&_text]:text-xs [&_text]:max-sm:text-base" tabIndex={0} role="region" aria-label={`Grafik ${kind} contoh, dapat digeser`}><svg className="block h-auto w-full min-w-140" viewBox="0 0 710 256" role="img" aria-label={kind==='latency'?'Latensi p95 per bucket, ms':kind==='status'?'HTTP 5xx per bucket':'Request selesai dan HTTP 5xx per bucket'}>
      {[0,1,2,3,4].map(i=><g key={i}><line x1="54" x2="640" y1={51+i*38.5} y2={51+i*38.5} className="stroke-line [stroke-dasharray:3_4]"/><text x="45" y={55+i*38.5} textAnchor="end">{number(top*(4-i)/4)}</text></g>)}
      <text x="54" y="23">{kind==='latency'?'p95 / bucket (ms)':kind==='status'?'HTTP 5xx / bucket':'Request / bucket'}</text>
      <path className="stroke-(--chart) [stroke-linejoin:round]" fill="none" strokeWidth="2.5" d={data.buckets.map((b,i)=>kind==='latency'&&b.p95===null?'':`${i===0||kind==='latency'&&data.buckets[i-1].p95===null?'M':'L'}${54+i*586/last},${205-(kind==='latency'?b.p95!:b.count)/top*154}`).join(' ')}/>
      {kind==='traffic'&&data.buckets.map((b,i)=><rect key={i} className="fill-(--chart-error)" x={51.5+i*586/last} y={205-b.errors/Math.max(4,...data.buckets.map(b=>b.errors))*154} width="5" height={b.errors/Math.max(4,...data.buckets.map(b=>b.errors))*154}><title>{`${b.errors} HTTP 5xx`}</title></rect>)}
      {kind==='traffic'&&[0,1,2,3,4].map(i=><text key={i} x="652" y={55+i*38.5}>{number(Math.max(4,...data.buckets.map(b=>b.errors))*(4-i)/4)}</text>)}
      {kind==='traffic'&&<text x="640" y="23" textAnchor="end">HTTP 5xx / bucket</text>}
      {data.buckets.filter((_,i)=>last===4||i%3===0||i===last).map(b=><text key={b.at} x={54+data.buckets.indexOf(b)*586/last} y="235" textAnchor="middle">{demoTime(b.at)}</text>)}
    </svg></div>;
  }
  const workspace=useWorkspace();
  if(!profiles[workspace.profile].permissions.includes('monitoring:read'))return <><PageTitle title="Overview" description="Monitoring API TonzToon"/><DemoBoundary permission="monitoring:read">{null}</DemoBoundary></>;
  return <>
    <PageTitle title="Overview" description="Pantau API. Temukan gangguan. Telusuri penyebabnya." action={<Button appearance="outline" onClick={()=>setDetail('snapshot')}><Icon name="clock"/>Tentang snapshot</Button>}/>
    <details className="group/demo mb-6 rounded-3xl border border-line bg-panel p-1" open><summary className="flex min-h-14.5 cursor-pointer list-none items-center justify-between gap-3 px-4 py-3.5 text-sm [&::-webkit-details-marker]:hidden"><strong>Demo lokal terhubung</strong><Badge>{sim.running?'Berjalan':'Dijeda'} · {scenarios[sim.scenario]}</Badge><span className="size-2 rotate-45 border-e-2 border-b-2 border-muted text-[0px] group-open/demo:rotate-225" aria-hidden="true">⌃</span></summary><div className="rounded-[20px] bg-surface p-5"><div className="flex flex-wrap items-end gap-2">
      <Select label="Environment simulasi" fieldClassName="w-34.5 max-w-full gap-2 text-xs/4 [&>label]:font-normal [&>label]:text-muted" value={demoEnv} onChange={e=>setDemoEnv(e.target.value)}><option value="production">Production</option><option value="staging">Staging</option></Select>
      <Select label="Skenario" fieldClassName="w-51.25 max-w-full gap-2 text-xs/4 [&>label]:font-normal [&>label]:text-muted" value={scenario} onChange={e=>setScenario(e.target.value as Scenario)}>{Object.entries(scenarios).map(([v,label])=><option key={v} value={v}>{label}</option>)}</Select>
      <Button variant="primary" onClick={()=>setSim(s=>({...s,running:!s.running}))}>{sim.running?'Jeda demo':'Mulai demo'}</Button>
      <Button appearance="outline" onClick={()=>setSim(s=>advance({...s,scenario,environment:demoEnv}))}>Jalankan skenario</Button>
      <Button appearance="outline" onClick={()=>setSim(advance)}>Langkah 30 detik</Button>
      <Button appearance="outline" onClick={()=>{setSim(createSimulation());setScenario('healthy');setDemoEnv('production');}}>Reset demo</Button>
    </div><p className="mt-3 text-xs/4 text-muted">Jam demo 28 Okt 2026, {demoTime(sim.now,true)} UTC+7 · 1 tick = 30 detik simulasi / 2 detik nyata. Sesi lokal · batas 1.000 event per feed · {sim.dropped} event keluar dari retensi.</p></div></details>
    <div className="flex flex-wrap items-center gap-3"><Select label="Environment monitoring" leading={<span className="size-1.5 rounded-full bg-accent"/>} className="rounded-control" fieldClassName={cx(hiddenLabel,"w-59.5 max-w-full")} value={env} onChange={e=>set('environment',e.target.value)}><option value="production">Production (contoh)</option><option value="staging">Staging (tanpa data awal)</option></Select><Tabs compact hidePanels label="Rentang waktu monitoring" value={range} onValueChange={v=>set('range',v)} items={[["5","5 menit"],["15","15 menit"],["60","1 jam"],["1440","24 jam"],["custom","Kustom"]].map(([v,label])=>({value:v,label,content:null}))}/><span className="ms-auto flex items-center gap-2 text-[13px] text-muted max-sm:ms-0 [&_svg]:size-3.75"><Icon name="clock"/>Snapshot contoh</span></div>
    {range==='custom'&&<CustomRange key={`${params.get('window_from')}:${params.get('window_to')}`} now={sim.now}/>}
    {window.error&&<Alert tone="error" title="Rentang tidak valid">{window.error}</Alert>}
    {range==='custom'&&partialWindow&&!window.error&&<Alert tone="warning" title="Cakupan rentang kustom parsial">Angka hanya mencakup event contoh yang masih tersimpan. Interval di luar cakupan fixture tidak dianggap sehat atau nol.</Alert>}
    <div className="flex flex-wrap justify-between gap-x-4 gap-y-1 py-4 text-xs/4 text-muted"><span>{periodDate(window.start)} sampai {periodDate(window.end)} · cutoff {demoTime(window.end,true)} UTC+7 · jam demo</span><span>observed_at {demoTime(sim.now,true)} · umur cutoff {number((sim.now-window.end)/1000)} dtk · Data contoh</span></div>
    {state!=='normal'&&<Alert tone={['error','denied'].includes(state)?'error':'warning'} title={stateLabels[state]} action={<Button appearance="outline" onClick={()=>set('state','normal')}>Kembali ke data contoh</Button>}>Simulasi lokal. {state==='stale'?'Data stale tidak menandakan pulih.':state==='denied'?'Izin monitoring ditolak; metrik disembunyikan.':'Data tidak lengkap atau tidak tersedia.'}</Alert>}
    {!hidden?<div className="@container">
      {activeScenario!=='healthy'&&activeScenario!=='burst'&&<section className="mb-6 flex flex-wrap items-start gap-4 rounded-3xl border border-(--warning-line) bg-(--incident-bg) p-6 [&>svg]:text-(--warning) [&>div]:min-w-48 [&>div]:flex-1 [&_p]:mt-2 [&_p]:text-sm" aria-label="Insiden contoh"><Icon name="alert"/><div><Badge tone="warning">Skenario gangguan · Contoh</Badge><h2>{scenarios[activeScenario]}</h2><p>Hasil skenario browser lokal. Evaluator insiden server belum terhubung.</p></div><Button variant="primary" onClick={()=>setDetail('incident')}>Periksa skenario<Icon name="chevron"/></Button></section>}
      <section className="grid grid-cols-2 gap-1 rounded-3xl bg-panel p-1 max-[359px]:grid-cols-1 @min-[56rem]:grid-cols-4" aria-label="Metrik API data contoh lokal">{[
        {label:'Request selesai',n:number(data.count),unit:'',note:`${number(data.rps,2)} req/s · reader`,icon:'requests'},
        {label:'HTTP 5xx',n:value(data.count?data.errors/data.count*100:null),unit:'%',note:`${data.errors} dari ${number(data.count)} respons`,icon:'error'},
        {label:'Latensi p95',n:value(data.p95),unit:'ms',note:`p50 ${value(data.p50)} ms · p99 ${value(data.p99)} ms`,icon:'timer'},
        {label:'Availability liveness',n:value(data.availability),unit:data.availability===null?'':'%',note:`${data.success}/${data.probes} probe · coverage ${coverageLabel}`,icon:'health'},
      ].map(m=><article className="min-w-0 rounded-2xl bg-surface p-4 sm:p-5" key={m.label}><div className="flex min-h-6 items-start justify-between gap-2 text-sm font-medium text-muted [&>svg]:size-4 [&>svg]:max-sm:hidden">{m.label}<Icon name={m.icon}/></div><div className="mt-4 text-[clamp(1.5rem,2.6vw,2.1rem)] leading-tight font-semibold tracking-[-.025em] wrap-anywhere">{m.n}<small className="ms-1 text-sm font-normal tracking-normal text-muted">{m.unit}</small></div><p className="mt-2 text-[13px]/relaxed text-muted">{m.note}</p></article>)}</section>
      <div className="flex flex-wrap justify-between gap-x-5 gap-y-2 px-2 py-4 text-xs/4 text-muted"><span>{data.inFlight} request in-flight pada snapshot selesai</span><span>HTTP 4xx: {data.count?`${number(data.clientErrors/data.count*100,2)}%`:'Belum tersedia'} ({data.clientErrors} respons)</span><span>Quantile dari event demo</span><span>Cakupan metrik: {partialWindow?'parsial / buffer terbatas':'fixture tersimpan'}</span></div>
      <div className="mb-6 grid items-stretch gap-5 @min-[64rem]:grid-cols-[minmax(0,1fr)_320px]"><Panel className="border border-line" headerClassName={panelHeader} bodyClassName="flex flex-1 flex-col p-0" title="Trafik & respons server" description={`${window.label} · ${env} · data contoh lokal`} actions={<div className="flex flex-wrap gap-4 text-xs text-muted"><span className="flex items-center gap-1.5"><i className="inline-block h-0.5 w-4 bg-(--chart)"/>Request selesai</span><span className="flex items-center gap-1.5"><i className="inline-block h-2.5 w-1.5 bg-(--chart-error)"/>HTTP 5xx</span></div>}>
        <Tabs className="px-4 pt-4 max-sm:px-2" appearance="underline" label="Metrik grafik" value={metric} onValueChange={v=>set('chart',v)} items={[["traffic","Trafik & 5xx"],["latency","Latensi"],["status","Status HTTP"]].map(([v,label])=>({value:v,label,content:chart(v)}))}/>
        <p className="px-4 pt-2 pb-3 text-xs text-muted">{number(data.count)} request · {data.errors} respons 5xx · {data.buckets.length} bucket contoh</p><details className="mx-4"><summary className={disclosure}>Lihat data grafik</summary><Table className={adminTable} caption="Data grafik contoh per bucket" data={data.buckets} columns={bucketColumns} getRowId={row=>String(row.at)}/></details>
      </Panel><Panel className="border border-line" headerClassName={panelHeader} bodyClassName="px-4 pt-0 pb-2" title="Kondisi layanan" description="Status dari probe contoh" actions={<Icon name="health"/>}><dl className="m-0">{[
        ["Layanan API","Probe GET / · setiap 5 detik",service],
        ["Database","Pemeriksaan ringan · cache 10 dtk","Belum diukur (demo)"],
        ["Pipeline telemetry","Metrik, agregasi, dan log",state==='stale'?'Status tidak diketahui':activeScenario==='gap'?'Ingest demo terputus':'Ingest demo aktif'],
        ["Koneksi browser","Frontend lokal · tanpa SSE",sim.running?'Demo browser berjalan':'Demo browser dijeda'],
      ].map(([label,note,status],i)=><div className="flex flex-wrap items-center justify-between gap-3 border-b border-line py-4 text-sm/5" key={label}><dt className="min-w-0 flex-[1_1_9rem]"><strong className="block font-medium">{label}</strong><small className="inline text-xs/4 text-muted">{note}</small></dt><dd className="ms-auto max-w-full text-end"><Badge className="min-h-6.5 border-0 px-2.5 py-1 leading-4.5" tone={i===0&&service==='Terjangkau'?'success':i===0&&service==='Tidak terjangkau'?'error':'neutral'}>{status}</Badge></dd></div>)}</dl><div className="flex items-start gap-2 pt-4 text-xs/relaxed text-muted [&>svg]:mt-0.5 [&>svg]:size-4"><Icon name="info"/><p>Liveness hanya memeriksa proses API. Auth, Storage, dan upstream belum dipantau.</p></div><Button variant="ghost" className="mt-2 px-2 text-xs" onClick={()=>setDetail('health')}>Lihat cakupan pemeriksaan<Icon name="chevron"/></Button></Panel></div>
      <Panel className="border border-line" headerClassName={panelHeader} bodyClassName="p-0" title="Endpoint yang perlu diperiksa" description="Prioritaskan error dan latensi pada rentang contoh." actions={<Link className={textLink} href={`/requests?${context}`}><Icon name="requests"/>Request log contoh</Link>}>
        <div className={cx(tableToolbar,"m-0 p-5")}><Input type="search" label="Cari endpoint Overview" fieldClassName={hiddenLabel} value={query} onChange={e=>set('q',e.target.value)} placeholder="Cari route endpoint…"/><Select label="Urutkan endpoint" value={sort} onChange={e=>{const next=new URLSearchParams(params);next.set('sort',e.target.value);next.delete('order');router.replace(`${path}?${next}`,{scroll:false});}}><option value="priority">Prioritas gangguan</option><option value="count">Request terbanyak</option><option value="errors">5xx terbanyak</option><option value="p95">Latensi tertinggi</option><option value="name">Route A–Z</option><option value="none">Tanpa urutan</option></Select></div>
        <Table className={cx(adminTable,"[&_:is(th,td)]:px-4.5 [&_:is(th,td)]:py-3.5 [&_thead_th]:bg-panel [&_thead_th]:text-xs [&_tbody_td:last-child]:w-11 [&_tbody_td:last-child]:py-1.5 [&_tbody_td:last-child]:ps-0 [&_tbody_td:last-child]:pe-3")} captionHidden caption="Endpoint API, data contoh. Geser untuk melihat semua kolom." data={data.endpoints} columns={columns}
          pagination={false} globalFilter={query} sorting={sorting} getRowId={row=>row.id}
          onSortingChange={update=>{const first=(typeof update==='function'?update(sorting):update)[0];const next=new URLSearchParams(params);
            next.set('sort',first?(first.id==='route'?'name':first.id):'none');if(first)next.set('order',first.desc?'desc':'asc');else next.delete('order');router.replace(`${path}?${next}`,{scroll:false});}}
          footer={({filteredRows,totalRows})=><div className="flex flex-wrap justify-between gap-2 px-5 py-4 text-xs text-muted"><span>{filteredRows} dari {totalRows} endpoint demo</span><span>Route template · Data contoh</span></div>}/>
        {query&&<Button onClick={()=>set('q','')}>Reset pencarian</Button>}
      </Panel>
      <div className="flex flex-wrap justify-between gap-3 px-2 pt-4 text-xs text-muted"><span>Pipeline demo: {sim.scenario==='gap'?'terputus':'terhubung'}</span><span>Event demo disimpan hingga batas 1.000; bukan sampling produksi</span><span>Metrik berasal dari event demo yang masih tersimpan</span></div>
    </div>:state==='normal'||state==='empty'?<Panel title="Ringkasan monitoring"><EmptyState announce icon="health" title="Belum ada data monitoring"
      description="Belum ada data pada environment dan rentang ini. Data yang tidak tersedia tidak dianggap nol atau sehat."
      action={env==='staging'?<Button appearance="outline" onClick={()=>set('environment','production')}>Lihat Production contoh</Button>:undefined}/></Panel>
      :<Panel title={stateLabels[state]}><p>Data tidak tersedia; tidak dianggap nol atau sehat.</p>{env==='staging'&&<Button appearance="outline" onClick={()=>set('environment','production')}>Lihat Production contoh</Button>}</Panel>}
    <footer className="mt-7 border-t border-line py-5 text-xs text-muted"><p><strong>Frontend interaktif · Data contoh lokal.</strong> Filter memperbarui metrik, grafik, dan endpoint contoh. Tidak ada request monitoring ke backend.</p><details><summary className={disclosure}>Contoh state tampilan</summary><Select fieldClassName="mb-4 max-w-96" label="State data" value={state} onChange={e=>set('state',e.target.value)}>{Object.entries(stateLabels).map(([v,label])=><option key={v} value={v}>{label}</option>)}</Select></details></footer>
    <Dialog open={detail!==null} onOpenChange={v=>{if(!v)setDetail(null);}} title={endpoint?'Detail endpoint':detail==='incident'?'Insiden contoh':detail==='health'?'Cakupan pemeriksaan':'Snapshot contoh'}>{endpoint?<><code>{endpoint.route}</code><dl className={detailList}><dt>Request selesai</dt><dd>{number(endpoint.count)}</dd><dt>HTTP 5xx</dt><dd>{endpoint.errors}</dd><dt>Latensi p95</dt><dd>{value(endpoint.p95,' ms')}</dd></dl><Link className={textLink} href={`/endpoints/${endpoint.id}?${context}`}>Buka halaman endpoint</Link></>:<p>{detail==='health'?'Liveness, database, pipeline telemetry dan koneksi browser diperiksa terpisah. Auth, Storage dan upstream belum dipantau.':'Sesi demo browser lokal, 28 Oktober 2026. Metrik, bucket dan endpoint dihitung dari event contoh yang sama, dengan batas retensi 1.000. Tidak ada request monitoring ke backend.'}</p>}</Dialog>
  </>;
}
