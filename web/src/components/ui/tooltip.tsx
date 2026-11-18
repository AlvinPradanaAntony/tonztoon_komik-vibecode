"use client";

import { cloneElement, useEffect, useId, useRef, type ReactElement } from "react";

export function Tooltip({label, enabled=true, children}: {label:string; enabled?:boolean; children:ReactElement<{"aria-describedby"?:string}>}) {
  const id=useId(); const ref=useRef<HTMLDivElement>(null);
  const hide=()=>ref.current?.hidePopover();
  useEffect(()=>{
    const close=()=>ref.current?.hidePopover();
    window.addEventListener('scroll',close,true);window.addEventListener('resize',close);
    return ()=>{window.removeEventListener('scroll',close,true);window.removeEventListener('resize',close);};
  },[]);
  useEffect(()=>{if(!enabled)ref.current?.hidePopover();},[enabled]);
  function show(target:HTMLElement){
    if(!enabled||!ref.current)return;
    const rect=target.getBoundingClientRect(),sidebar=target.closest('aside')?.getBoundingClientRect();
    const tooltip=ref.current;tooltip.showPopover();
    tooltip.style.left=`${Math.min((sidebar?.right??rect.right)+12,innerWidth-tooltip.offsetWidth-12)}px`;
    tooltip.style.top=`${Math.max(12,Math.min(rect.top+(rect.height-tooltip.offsetHeight)/2,innerHeight-tooltip.offsetHeight-12))}px`;
  }
  return <><span className="contents"
    onPointerEnter={event=>{if(event.pointerType!=='touch'){const target=event.currentTarget.querySelector<HTMLElement>('a,button');if(target)show(target);}}}
    onPointerLeave={hide} onFocus={event=>show(event.target)} onBlur={hide}
    onKeyDown={event=>{if(event.key==='Escape')hide();}}>
    {cloneElement(children, {"aria-describedby": enabled ? [children.props['aria-describedby'],id].filter(Boolean).join(' ') : children.props['aria-describedby']})}
  </span><div ref={ref} id={id} role="tooltip" popover="manual" className="pointer-events-none fixed inset-auto m-0 rounded-lg border border-line bg-surface px-3 py-2 text-sm text-foreground shadow-[0_4px_14px_#00000014]">{label}</div></>;
}
