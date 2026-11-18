"use client";
import Image from "next/image";
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { usePathname } from "next/navigation";
import { Suspense, useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { Badge, Button, Dialog, Drawer, Icon, ScrollArea, ThemeToggle, Tooltip } from "@/components/ui";
import { cx } from "@/components/ui/types";
import { iconButton } from "@/components/ui/styles";
import { useSimulation } from "@/lib/monitoring/demo-store";
import { evaluateAlerts } from "@/lib/monitoring/demo-adapter";
import { MonitoringPump } from "./monitoring-pump";

const fadeOnCollapse="transition-opacity duration-180 lg:group-data-[sidebar=collapsed]/admin:pointer-events-none lg:group-data-[sidebar=collapsed]/admin:opacity-0";
const navLink="relative my-1 flex h-11 min-h-11 w-full cursor-pointer items-center overflow-hidden rounded-lg border-0 bg-transparent p-0 text-start whitespace-nowrap text-muted transition-[background-color,color,filter] duration-150 hover:bg-[light-dark(var(--line),var(--surface-alt))] hover:text-foreground aria-[current=page]:bg-line aria-[current=page]:font-semibold aria-[current=page]:text-foreground";

const navigation: {group:string;items:{label:string;href?:string;icon:string}[]}[] = [
  {group:"Monitoring",items:[{label:"Overview",href:"/overview",icon:"overview"},{label:"Endpoint",href:"/endpoints",icon:"endpoint"},{label:"Request log",href:"/requests",icon:"requests"},{label:"Log runtime",href:"/runtime-logs",icon:"audit"},{label:"Health",href:"/health",icon:"health"},{label:"Alert",href:"/alerts",icon:"alert"}]},
  {group:"Preview Komik",items:[{label:"Preview Komik",href:"/comic-preview",icon:"book"}]},
  {group:"Data",items:[{label:"Katalog & chapter",href:"/data/comics",icon:"book"},{label:"Genre",href:"/data/genres",icon:"tag"},{label:"Source",href:"/data/sources",icon:"model"},{label:"Akun",href:"/data/accounts",icon:"users"},{label:"Helpdesk",href:"/data/helpdesk",icon:"help"},{label:"Audit",href:"/data/audit",icon:"audit"}]},
  {group:"Alur & model",items:[{label:"Data flow",href:"/data-flow",icon:"flow"},{label:"ERD explorer",href:"/data-model",icon:"model"}]},
];
type NavigationMenuProps = {
  mobile: boolean;
  expanded: boolean | null;
  onNavigate: () => void;
  onUnavailable: (label: string) => void;
};
function NavigationMenu({ mobile, expanded, onNavigate, onUnavailable, pathname }: NavigationMenuProps & { pathname?: string }) {
  const [simulation]=useSimulation();
  const alertCount=evaluateAlerts(simulation,'production').filter(alert=>['pending','firing'].includes(alert.state)).length;
  return <nav aria-label={mobile?"Navigasi mobile dan tablet":"Navigasi admin"}>{navigation.map(({group,items},index)=><div key={group}><p className={cx("relative mb-1 h-7 min-h-7 overflow-hidden px-1 text-[11px]/7 font-semibold tracking-[.04em] whitespace-nowrap text-muted transition-colors duration-180 after:absolute after:inset-x-1 after:top-1/2 after:h-px after:bg-line after:opacity-0 after:transition-opacity after:duration-180 lg:group-data-[sidebar=collapsed]/admin:text-transparent lg:group-data-[sidebar=collapsed]/admin:after:opacity-100",index===0?"mt-1":"mt-3.5")}>{group}</p>{items.map(item=>{
    const content=<><span className="inline-flex size-11 min-w-11 items-center justify-center [&_svg]:size-4.5"><Icon name={item.icon}/></span><span className={cx("ms-2 min-w-0 overflow-hidden text-sm text-ellipsis",fadeOnCollapse)}>{item.label}</span>{item.label==='Alert'&&alertCount>0&&<span className="me-3 ms-auto rounded-full bg-(--warning-bg) px-2 py-0.5 text-[11px] text-(--warning) lg:group-data-[sidebar=collapsed]/admin:absolute lg:group-data-[sidebar=collapsed]/admin:start-6 lg:group-data-[sidebar=collapsed]/admin:top-1 lg:group-data-[sidebar=collapsed]/admin:m-0 lg:group-data-[sidebar=collapsed]/admin:size-4 lg:group-data-[sidebar=collapsed]/admin:p-0 lg:group-data-[sidebar=collapsed]/admin:text-center" aria-label={`${alertCount} insiden perlu diperiksa`}>{alertCount}</span>}</>;
    return <Tooltip key={item.label} label={item.label} enabled={!mobile&&expanded===false}>{item.href?<Link className={navLink} href={item.href} aria-label={item.label} aria-current={(pathname?.startsWith(item.href)||item.href==='/data/comics'&&pathname?.startsWith('/data/chapters'))?'page':undefined} onClick={onNavigate}>{content}</Link>:<button className={navLink} onClick={()=>{onNavigate();onUnavailable(item.label);}}>{content}</button>}</Tooltip>;
  })}</div>)}</nav>;
}
function RouteNavigation(props: NavigationMenuProps) {
  const pathname = usePathname();
  return <NavigationMenu {...props} pathname={pathname} />;
}
function CurrentPageLabel() {
  const pathname = usePathname();
  const current = navigation.flatMap(group=>group.items).find(item => item.href && (pathname.startsWith(item.href)||item.href==='/data/comics'&&pathname.startsWith('/data/chapters')));
  const tail=pathname.split('/').filter(Boolean).slice(current?.href?.split('/').filter(Boolean).length??1).map(decodeURIComponent).join(' / ');
  return <span className="flex min-w-0 flex-wrap items-center gap-2"><Link className="font-medium text-foreground" href={current?.href??'/data/comics'}>{current?.label??'Chapter'}</Link>{tail&&<><span aria-hidden="true">/</span><strong className="max-w-48 truncate font-medium text-foreground">{tail}</strong></>}</span>;
}
function subscribe(callback:()=>void) {window.addEventListener("resize",callback);return ()=>window.removeEventListener("resize",callback);}
function preference() {try{const v=sessionStorage.getItem("tt-admin-sidebar");if(v==="expanded"||v==="collapsed")return v==="expanded";}catch{}return matchMedia("(min-width:1280px)").matches;}
export function AdminShell({children}:{children:ReactNode}) {
  const preferred=useSyncExternalStore(subscribe,preference,()=>null);
  const [manual,setManual]=useState<boolean|null>(null);const expanded=manual??preferred;
  const [open,setOpen]=useState(false);const [pending,setPending]=useState("");
  const mobileButton=useRef<HTMLButtonElement>(null);const desktopButton=useRef<HTMLButtonElement>(null);
  useEffect(()=>{const mq=matchMedia("(min-width:1024px)");const change=()=>{
    const active=document.activeElement;
    if(mq.matches){setOpen(false);if(active?.closest('#mobile-nav')||active===mobileButton.current)requestAnimationFrame(()=>desktopButton.current?.focus());}
    else if(active?.closest('.tt-sidebar'))mobileButton.current?.focus();
  };mq.addEventListener('change',change);return ()=>mq.removeEventListener('change',change);},[]);
  function toggle(){const next=!(expanded??matchMedia('(min-width:1280px)').matches);setManual(next);try{sessionStorage.setItem('tt-admin-sidebar',next?'expanded':'collapsed');}catch{}}
  const brand=<Link className="flex min-h-11 min-w-0 flex-1 items-center gap-2 text-lg font-[750] tracking-[-.04em] text-foreground" href="/overview" aria-label="TonzToon Admin, kembali ke Overview"><Image className="mx-1 h-10 w-9 shrink-0 object-contain" src="/logo.png" alt="" width={36} height={40} priority/><span className={cx("flex min-w-0 flex-col overflow-hidden leading-tight",fadeOnCollapse)}>TonzToon<small className="mt-0.5 block text-[11px] font-medium tracking-[.02em] whitespace-nowrap text-muted">ADMIN CONSOLE</small></span></Link>;
  function links(mobile=false){
    const props={mobile,expanded,onNavigate:()=>setOpen(false),onUnavailable:setPending};
    return <Suspense fallback={<NavigationMenu {...props}/>}><RouteNavigation {...props}/></Suspense>;
  }
  return <div className="tt-admin group/admin flow-root min-h-dvh tabular-nums [--sidebar-width:80px] xl:[--sidebar-width:240px] data-[sidebar=expanded]:[--sidebar-width:240px] data-[sidebar=collapsed]:[--sidebar-width:80px] motion-reduce:[&&_*]:animate-none motion-reduce:[&&_*]:transition-none motion-reduce:[&&_*]:scroll-auto" data-sidebar={expanded===null?undefined:expanded?'expanded':'collapsed'}>
    <MonitoringPump/>
    <aside className="tt-sidebar fixed inset-y-0 start-0 z-40 hidden w-(--sidebar-width) flex-col overflow-hidden px-4.5 pt-4 transition-[width] duration-280 ease-[cubic-bezier(.4,0,.2,1)] lg:flex" aria-label="Navigasi desktop">
      <header className="relative mb-3 h-11 shrink-0 transition-[height] duration-280 group-data-[sidebar=collapsed]/admin:h-25 [&>a]:absolute [&>a]:start-0 [&>a]:top-0 [&>a]:h-11 [&>a]:overflow-hidden">{brand}<Button ref={desktopButton} variant="ghost" className={cx(iconButton,"absolute start-0 top-0 z-2 translate-x-40 transition-transform duration-280 ease-[cubic-bezier(.4,0,.2,1)] group-data-[sidebar=collapsed]/admin:translate-x-0 group-data-[sidebar=collapsed]/admin:translate-y-14")} onClick={toggle} aria-label="Ubah lebar sidebar" aria-expanded={expanded??undefined} aria-controls="desktop-nav"><span className="absolute inset-0 flex items-center justify-center transition-[opacity,transform] duration-280 group-data-[sidebar=collapsed]/admin:pointer-events-none group-data-[sidebar=collapsed]/admin:scale-70 group-data-[sidebar=collapsed]/admin:rotate-90 group-data-[sidebar=collapsed]/admin:opacity-0"><Icon name="collapse"/></span><span className="pointer-events-none absolute inset-0 flex scale-70 -rotate-90 items-center justify-center opacity-0 transition-[opacity,transform] duration-280 group-data-[sidebar=collapsed]/admin:pointer-events-auto group-data-[sidebar=collapsed]/admin:scale-100 group-data-[sidebar=collapsed]/admin:rotate-0 group-data-[sidebar=collapsed]/admin:opacity-100"><Icon name="expand"/></span></Button></header>
      <div id="desktop-nav" className="min-h-0 flex-1 overflow-hidden"><ScrollArea label="Menu admin desktop" className="h-full" refreshKey={expanded}>{links()}</ScrollArea></div>
      <footer className="flex h-16 min-h-16 shrink-0 items-center gap-2 overflow-hidden border-t border-line text-sm"><span className="flex size-10 shrink-0 items-center justify-center rounded-2xl bg-surface-alt text-[11px]" aria-hidden="true">AD</span><span className={fadeOnCollapse}>Admin<small className="block text-[11px] text-muted">Frontend contoh</small></span><Icon className={cx("ms-auto size-5 shrink-0",fadeOnCollapse)} name="lock"/></footer>
    </aside>
    <div className="min-h-dvh min-w-0 bg-canvas lg:my-4 lg:me-4 lg:ms-(--sidebar-width) lg:min-h-[calc(100dvh-32px)] lg:overflow-clip lg:rounded-[28px] lg:border lg:border-line lg:shadow-[0_2px_12px_#0f172a04] lg:transition-[margin-left] lg:duration-280">
      <header className="flex min-h-20 flex-wrap items-center gap-3 border-b border-line px-4 py-3 max-sm:min-h-19 sm:px-7">
        <Button ref={mobileButton} variant="ghost" className={cx(iconButton,"lg:hidden")} onClick={()=>setOpen(true)} aria-label="Buka menu navigasi" aria-expanded={open} aria-controls="mobile-nav"><Icon name="menu"/></Button>
        <nav className="flex min-w-0 flex-1 items-center gap-3 text-sm text-muted max-sm:hidden" aria-label="Breadcrumb"><Suspense fallback={<strong className="inline-block h-5 w-20" aria-hidden="true" />}><CurrentPageLabel /></Suspense></nav>
        <span className="ms-auto flex items-center gap-3"><Badge className="max-sm:hidden">Frontend · Data contoh</Badge><Link className="inline-flex min-h-11 items-center text-xs underline max-sm:hidden" href="/login">Login contoh</Link><ThemeToggle/></span>
      </header>
      <main id="konten" tabIndex={-1} className="mx-auto min-w-0 max-w-[1660px] px-4 py-5 focus:outline-none sm:p-7 [&>.alert]:mb-6 [&>section]:mb-6">{children}</main>
      <footer className="flex flex-wrap justify-between gap-2 border-t border-line p-4 text-xs text-muted sm:px-7"><span>TonzToon Admin / Frontend contoh</span><Link className="underline" href="/">Pemeriksaan komponen</Link><span>API bisnis <code>/api/v1</code> · Belum terhubung</span></footer>
    </div>
    <Drawer id="mobile-nav" className="motion-reduce:**:transition-none" panelClassName="pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)]" headerClassName="p-4" bodyClassName="overflow-hidden px-4 pb-4" open={open} onOpenChange={setOpen} title="Menu navigasi" headerContent={brand} closeIcon={<Icon name="close"/>}><ScrollArea label="Menu admin mobile" className="h-full" refreshKey={open}>{links(true)}</ScrollArea></Drawer>
    <Dialog open={!!pending} onOpenChange={v=>{if(!v)setPending('');}} title={pending||'Halaman'}><p>Halaman {pending} belum dimigrasikan ke Next.js. Struktur navigasi mengikuti prototype; implementasinya tetap bagian fase 2.</p></Dialog>
  </div>;
}
