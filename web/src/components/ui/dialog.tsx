"use client";

import { useEffect, useId, useRef, type ComponentProps, type ReactNode } from "react";
import { Button } from "./button";
import { cx, type UiSize } from "./types";
import { iconButton } from "./styles";

export type DialogProps = Omit<ComponentProps<"dialog">, "open" | "title" | "ref"> & {
  open: boolean; onOpenChange: (open: boolean) => void; title: string; description?: ReactNode;
  actions?: ReactNode; headerContent?: ReactNode; closeIcon?: ReactNode; closeLabel?: string; size?: UiSize; presentation?: "dialog" | "drawer"; side?: "start" | "end";
  headerClassName?: string; bodyClassName?: string; panelClassName?: string;
};

export function Dialog({ open, onOpenChange, title, description, actions, headerContent, closeIcon, closeLabel = "Tutup",
  size = "md", presentation = "dialog", side = "start", children, className, onClose, onCancel, onKeyDown,
  onPointerDown, onPointerCancel, onClick, headerClassName, bodyClassName, panelClassName, ...props }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null);
  const pointerStartedOutside = useRef(false);
  const titleId = useId();
  const descriptionId = useId();
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    pointerStartedOutside.current = false;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
    return () => { if (dialog.open) dialog.close(); };
  }, [open]);

  return <dialog {...props} ref={ref} aria-labelledby={titleId}
    aria-describedby={[description ? descriptionId : null, props["aria-describedby"]].filter(Boolean).join(" ") || undefined}
    data-presentation={presentation} data-side={side} data-size={size}
    className={cx("modal tt-overlay bg-transparent transition-discrete",presentation==='drawer'?"p-0":"p-4",size==='sm'?"[--tt-overlay-padding:var(--tt-space-sm)]":size==='lg'?"[--tt-overlay-padding:var(--tt-space-lg)]":"[--tt-overlay-padding:var(--tt-space-md)]",presentation==='drawer'?(side==='start'?"modal-start justify-items-start [--tt-overlay-closed-transform:translate3d(-100%,0,0)]":"modal-end justify-items-end [--tt-overlay-closed-transform:translate3d(100%,0,0)]"):"[--tt-overlay-closed-transform:scale(.96)]",className)}
    onPointerDown={(event) => {
      onPointerDown?.(event);
      pointerStartedOutside.current = !event.defaultPrevented && event.isPrimary
        && event.button === 0 && event.target === event.currentTarget;
    }}
    onPointerCancel={(event) => {
      pointerStartedOutside.current = false;
      onPointerCancel?.(event);
    }}
    onClick={(event) => {
      const startedOutside = pointerStartedOutside.current;
      pointerStartedOutside.current = false;
      onClick?.(event);
      if (event.defaultPrevented || !startedOutside || !event.currentTarget.open
        || event.target !== event.currentTarget) return;
      const panel = event.currentTarget.querySelector(".tt-overlay-panel")?.getBoundingClientRect();
      if (panel && (event.clientX < panel.left || event.clientX > panel.right
        || event.clientY < panel.top || event.clientY > panel.bottom)) onOpenChange(false);
    }}
    onKeyDown={(event) => {
      onKeyDown?.(event);
      if (event.defaultPrevented || event.key !== "Tab") return;
      const controls = Array.from(event.currentTarget.querySelectorAll<HTMLElement>(
        'button, a[href], input, select, textarea, summary, [tabindex], [contenteditable="true"]',
      )).filter((control) => control.tabIndex >= 0 && !control.matches(":disabled")
        && control.getClientRects().length > 0 && getComputedStyle(control).visibility === "visible");
      const first = controls[0];
      const last = controls.at(-1);
      if (event.shiftKey && event.target === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && event.target === last) { event.preventDefault(); first?.focus(); }
    }}
    onCancel={(event) => {
      onCancel?.(event);
      if (!event.defaultPrevented) {
        event.preventDefault();
        onOpenChange(false);
      }
    }}
    onClose={(event) => {
      // A queued close event may arrive after Strict Mode or a rapid reopen.
      if (event.currentTarget.open) return;
      onOpenChange(false);
      onClose?.(event);
    }}>
    <div className={cx("modal-box tt-overlay-panel grid grid-rows-[auto_minmax(0,1fr)_auto] overflow-visible bg-surface p-0 text-foreground",presentation==='drawer'?"h-dvh max-h-dvh max-w-[calc(100vw-1.5rem)] border-0":"max-h-[calc(100dvh-2rem)] max-w-[calc(100vw-2rem)] rounded-panel border border-line",
      presentation==='drawer'?(size==='sm'?"w-[min(var(--tt-drawer-sm),calc(100vw-1.5rem))]":size==='lg'?"w-[min(var(--tt-drawer-lg),calc(100vw-1.5rem))]":"w-[min(var(--tt-drawer-md),calc(100vw-1.5rem))]"):(size==='sm'?"w-[min(100%,var(--tt-dialog-sm))]":size==='lg'?"w-[min(100%,var(--tt-dialog-lg))]":"w-[min(100%,var(--tt-dialog-md))]"),presentation==='drawer'&&(side==='start'?"rounded-s-none rounded-e-panel":"rounded-e-none rounded-s-panel"),panelClassName)}>
      <header className={cx("flex flex-wrap items-center justify-between gap-4 border-b border-line",headerClassName??"p-(--tt-overlay-padding)")}><h2 id={titleId} className={headerContent ? "sr-only" : "text-base font-semibold"}>{title}</h2>{headerContent}
        <Button size="sm" variant={closeIcon ? "ghost" : "secondary"} className={closeIcon ? iconButton : undefined} onClick={() => onOpenChange(false)} aria-label={`${closeLabel}: ${title}`}>{closeIcon ?? closeLabel}</Button>
      </header>
      <div className={cx("min-h-0",bodyClassName??"overflow-auto p-(--tt-overlay-padding)")}>
        {description && <p id={descriptionId} className="mb-4 text-muted">{description}</p>}{children}
      </div>
      {actions && <footer className="flex flex-wrap items-center justify-between gap-4 border-t border-line p-(--tt-overlay-padding)">{actions}</footer>}
    </div>
  </dialog>;
}
