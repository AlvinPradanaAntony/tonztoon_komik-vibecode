"use client";

import { useId, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { cx } from "./types";

export type TabItem = { value: string; label: ReactNode; content: ReactNode; disabled?: boolean };
export type TabsProps = {
  items: TabItem[]; label: string; value?: string; defaultValue?: string;
  onValueChange?: (value: string) => void; className?: string; appearance?: "segmented" | "underline";
  compact?: boolean; hidePanels?: boolean;
};

export function Tabs({ items, label, value, defaultValue, onValueChange, className, appearance = "segmented", compact=false, hidePanels=false }: TabsProps) {
  const id = useId();
  const [internalValue, setInternalValue] = useState(defaultValue ?? items.find(item => !item.disabled)?.value);
  const requested = value ?? internalValue;
  const selected = items.find(item => item.value === requested && !item.disabled)?.value ?? items.find(item => !item.disabled)?.value;
  const track = useRef<HTMLDivElement>(null);
  const marker = useRef<HTMLSpanElement>(null);
  const structure = items.map(item => item.value).join("\u0000");
  useLayoutEffect(() => {
    const element = track.current;
    const indicator = marker.current;
    if (!element || !indicator) return;
    const update = () => {
      const active = element.querySelector<HTMLElement>('[aria-selected="true"]');
      indicator.style.visibility = active ? "visible" : "hidden";
      if (!active) return;
      indicator.style.width = `${active.offsetWidth}px`;
      indicator.style.height = `${active.offsetHeight}px`;
      indicator.style.transform = `translate(${active.offsetLeft}px, ${active.offsetTop}px)`;
    };
    update();
    const observer = new ResizeObserver(update);
    observer.observe(element);
    element.querySelectorAll('[role="tab"]').forEach(tab => observer.observe(tab));
    return () => observer.disconnect();
  }, [selected, structure]);
  function select(next: string) {
    if (next === selected) return;
    if (value === undefined) setInternalValue(next);
    onValueChange?.(next);
  }
  return <div className={cx("tt-tabs min-w-0", compact&&"max-sm:w-full",className)} data-appearance={appearance}>
    <div className="-m-1.5 overflow-x-auto p-1.5">
      <div ref={track} role="tablist" aria-label={label} aria-orientation="horizontal" className={cx("tabs relative isolate flex gap-0 shadow-none",appearance==='underline'?"min-w-0 flex-wrap rounded-none border-b border-line bg-transparent p-0":"min-w-max flex-nowrap rounded-lg p-1",compact?"w-auto bg-surface-alt max-sm:w-full":"w-full",appearance==='segmented'&&!compact&&"bg-panel")}
        onKeyDown={event => {
          if (event.altKey || event.ctrlKey || event.metaKey) return;
          const buttons = Array.from(event.currentTarget.querySelectorAll<HTMLButtonElement>('[role="tab"]:not(:disabled)'));
          const current = buttons.indexOf(event.target as HTMLButtonElement);
          if (current < 0) return;
          const rtl = getComputedStyle(event.currentTarget).direction === "rtl";
          let index: number;
          if (event.key === "Home") index = 0;
          else if (event.key === "End") index = buttons.length - 1;
          else if (event.key === "ArrowRight") index = (current + (rtl ? -1 : 1) + buttons.length) % buttons.length;
          else if (event.key === "ArrowLeft") index = (current + (rtl ? 1 : -1) + buttons.length) % buttons.length;
          else return;
          event.preventDefault();
          const next = buttons[index];
          next.focus();
          next.scrollIntoView({ block: "nearest", inline: "nearest" });
          select(next.dataset.value!);
        }}>
        <span ref={marker} className={cx("tt-tabs-marker pointer-events-none absolute start-0 top-0 z-0 rounded-md bg-surface transition-[transform,width,height] duration-300 ease-[cubic-bezier(.2,0,0,1)] motion-reduce:transition-none",appearance==='underline'&&"hidden",!compact&&"shadow-[0_1px_3px_rgb(0_0_0/0.1)]")} aria-hidden="true" />
        {items.map((item, index) => <button key={item.value} type="button" role="tab" data-value={item.value}
          id={`${id}-tab-${index}`} aria-controls={`${id}-panel-${index}`} aria-selected={selected === item.value}
          disabled={item.disabled} aria-disabled={item.disabled || undefined} tabIndex={selected === item.value ? 0 : -1}
          className={cx("tab relative z-1 inline-flex h-11 min-w-11 cursor-pointer items-center justify-center bg-transparent bg-none text-sm/normal whitespace-nowrap text-muted shadow-none before:content-none after:content-none aria-selected:text-foreground focus-visible:outline-[length:var(--tt-focus-width)] focus-visible:outline-solid focus-visible:outline-accent focus-visible:-outline-offset-3 disabled:cursor-not-allowed disabled:text-subtle disabled:opacity-100 enabled:hover:text-foreground",
            appearance==='underline'?"-mb-px flex-none rounded-t-md rounded-b-none border-0 border-b-2 border-transparent px-3 font-normal aria-selected:border-foreground aria-selected:font-semibold":"flex-[1_0_auto] rounded-md border-0 px-3.5 font-medium",
            compact&&"flex-none px-3 font-normal aria-selected:font-semibold max-sm:flex-1 max-sm:px-2")}
          onClick={() => select(item.value)}>{item.label}</button>)}
      </div>
    </div>
    <div className={cx("grid",appearance==='segmented'&&"mt-2",hidePanels&&"hidden")}>
    {items.map((item, index) => <div key={item.value} role="tabpanel" id={`${id}-panel-${index}`}
      aria-labelledby={`${id}-tab-${index}`} tabIndex={0} hidden={selected !== item.value}
      inert={selected !== item.value} aria-hidden={selected !== item.value}
      className="tt-tabs-panel col-start-1 row-start-1 block min-w-0 self-start opacity-100 transition-[opacity,display] duration-220 ease-in-out transition-discrete [&[hidden]]:pointer-events-none [&[hidden]]:hidden [&[hidden]]:opacity-0 motion-reduce:transition-none">{item.content}</div>)}
    </div>
  </div>;
}
