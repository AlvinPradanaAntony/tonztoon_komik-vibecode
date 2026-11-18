import type { ComponentProps, ReactNode } from "react";

const shapes: Record<string, ReactNode> = {
  overview: <><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></>,
  endpoint: <path d="m8 5-6 7 6 7m8-14 6 7-6 7M14 3l-4 18"/>,
  requests: <><path d="M8 5h13M8 12h13M8 19h13"/><path d="M3 5h.01M3 12h.01M3 19h.01" strokeWidth="3"/></>,
  audit: <path d="M7 3h12v18H5V5h2m1-2v4h8V3H8Zm1 9h6m-6 4h6"/>,
  health: <path d="M2 12h4l3-8 5 16 3-8h5"/>,
  alert: <><path d="m12 3 10 18H2L12 3Z"/><path d="M12 9v5m0 3v.01"/></>,
  book: <path d="M12 5v16M3 3c4 0 6 0 9 2 3-2 5-2 9-2v16c-4 0-6 0-9 2-3-2-5-2-9-2V3Z"/>,
  tag: <><path d="M3 3h8l10 10-8 8L3 11V3Z"/><circle cx="7.5" cy="7.5" r="1"/></>,
  model: <><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 4 18 4 18 0V5M3 12c0 4 18 4 18 0"/></>,
  users: <><circle cx="9" cy="8" r="3"/><path d="M3 21v-3a6 6 0 0 1 12 0v3m1-17a3 3 0 0 1 0 6m2 4a5 5 0 0 1 3 5v2"/></>,
  help: <path d="M4 14v-3a8 8 0 0 1 16 0v3M4 12H2v7h5v-7H4Zm16 0h2v7h-5v-7h3Zm0 7c0 3-4 3-7 3"/>,
  flow: <><rect x="8" y="2" width="8" height="5"/><rect x="2" y="17" width="7" height="5"/><rect x="15" y="17" width="7" height="5"/><path d="M12 7v5M5 17v-5h14v5"/></>,
  collapse: <><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16m7-12-4 4 4 4"/></>,
  expand: <><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16m4-12 4 4-4 4"/></>,
  moon: <path d="M21 13a9 9 0 0 1-10-10A9 9 0 1 0 21 13Z"/>,
  sun: <><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/></>,
  clock: <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
  timer: <><circle cx="12" cy="14" r="8"/><path d="M9 2h6m-3 4V2m0 8v5m6-8 2-2"/></>,
  error: <><circle cx="12" cy="12" r="9"/><path d="m9 9 6 6m0-6-6 6"/></>,
  lock: <><rect x="5" y="10" width="14" height="11"/><path d="M8 10V6a4 4 0 0 1 8 0v4m-4 5v2"/></>,
  menu: <path d="M3 5h18M3 12h18M3 19h18"/>,
  chevron: <path d="m9 5 7 7-7 7"/>,
  close: <path d="m5 5 14 14m0-14L5 19"/>,
  search: <><circle cx="10" cy="10" r="7"/><path d="m15 15 6 6"/></>,
  info: <><circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v.01"/></>,
};

export function Icon({name,className,...props}: ComponentProps<"svg"> & {name:keyof typeof shapes}) {
  return <svg className={className??"size-5 shrink-0 align-middle"} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="square" strokeLinejoin="miter" aria-hidden="true" focusable="false" {...props}>{shapes[name]}</svg>;
}
