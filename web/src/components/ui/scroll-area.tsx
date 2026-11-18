"use client";

import { useEffect, useRef, type ReactNode } from "react";
import { OverlayScrollbarsComponent, type OverlayScrollbarsComponentRef } from "overlayscrollbars-react";
import { cx } from "./types";

export function ScrollArea({ children, label, className, refreshKey, axis="vertical" }: {
  children: ReactNode; label: string; className?: string; refreshKey?: unknown; axis?:"vertical"|"both";
}) {
  const ref = useRef<OverlayScrollbarsComponentRef>(null);
  useEffect(() => {
    const frame = requestAnimationFrame(() => ref.current?.osInstance()?.update(true));
    return () => cancelAnimationFrame(frame);
  }, [refreshKey]);
  return <OverlayScrollbarsComponent ref={ref} defer className={cx("tt-scroll-area min-h-0 min-w-0 [&_[data-overlayscrollbars-viewport]]:overscroll-contain [&_[data-overlayscrollbars-viewport]:focus-visible]:outline-3 [&_[data-overlayscrollbars-viewport]:focus-visible]:outline-accent [&_[data-overlayscrollbars-viewport]:focus-visible]:-outline-offset-3 [&:has(:focus-visible)_.os-scrollbar]:visible [&:has(:focus-visible)_.os-scrollbar]:opacity-100",className)}
    options={{overflow:{x:axis==='both'?'scroll':'hidden',y:'scroll'},scrollbars:{theme:'tt-scrollbars',autoHide:'leave',autoHideDelay:700}}}
    events={{initialized:instance=>{const viewport=instance.elements().viewport;
      viewport.tabIndex=0;viewport.setAttribute('role','region');viewport.setAttribute('aria-label',label);
    }}}>{children}</OverlayScrollbarsComponent>;
}
