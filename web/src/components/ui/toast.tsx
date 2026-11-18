"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { Button } from "./button";
import { Spinner } from "./spinner";
import { cx, type UiTone } from "./types";

export type ToastPosition = "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right";
export type ToastOptions = {
  title: string; description?: string; tone?: UiTone; position?: ToastPosition;
  /** Milliseconds; zero keeps the toast until dismissed. Actions default to persistent. */
  duration?: number; content?: ReactNode; loading?: boolean;
  action?: { label: string; onClick: () => void | Promise<unknown>; closeOnClick?: boolean };
};
type ToastMessage = string | Omit<ToastOptions, "loading" | "position">;
export type ToastPromiseOptions<T> = {
  loading: ToastMessage; success: ToastMessage | ((value: T) => ToastMessage);
  error: ToastMessage | ((error: unknown) => ToastMessage); position?: ToastPosition; duration?: number;
};
export type ToastPromiseResult<T> = { id: string; promise: Promise<T> };
type ToastFunction = {
  (options: ToastOptions): string;
  promise: <T>(task: Promise<T> | (() => Promise<T>), options: ToastPromiseOptions<T>) => ToastPromiseResult<T>;
};
type Entry = ToastOptions & { id: string; position: ToastPosition; duration: number; trigger: HTMLElement | null; closing?: boolean; revision: number };
type ToastApi = { show: (options: ToastOptions) => string; promiseToast: ToastFunction["promise"]; dismiss: (id: string) => void; dismissAll: () => void };
const messageOptions = (message: ToastMessage): Omit<ToastOptions, "loading" | "position"> => typeof message === "string" ? { title: message } : message;
const durationFor = (options: ToastOptions) => {
  const duration = options.loading ? 0 : options.duration ?? (options.action || options.content ? 0 : 5000);
  return Number.isFinite(duration) ? Math.max(0, duration) : 5000;
};
const ToastContext = createContext<ToastApi | null>(null);
const positions: ToastPosition[] = ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"];

export function useToast() {
  const context = useContext(ToastContext);
  const api = useMemo(() => context ? {
    toast: Object.assign((options: ToastOptions) => context.show(options), {
      promise: <T,>(task: Promise<T> | (() => Promise<T>), options: ToastPromiseOptions<T>) => context.promiseToast(task, options),
    }), dismiss: context.dismiss, dismissAll: context.dismissAll,
  } : null, [context]);
  if (!context) throw new Error("useToast harus berada di dalam ToastProvider.");
  return api!;
}

export function ToastProvider({ children, layout = "stacked" }: { children: ReactNode; layout?: "stacked" | "expanded" }) {
  const [entries, setEntries] = useState<Entry[]>([]);
  const [hidden, setHidden] = useState(false);
  const [announcement, setAnnouncement] = useState<{ text: string; tone: UiTone }>({ text: "", tone: "neutral" });
  const nextId = useRef(0);
  const activeIds = useRef(new Set<string>());
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    const ids = activeIds.current;
    const update = () => setHidden(document.hidden);
    update(); document.addEventListener("visibilitychange", update);
    return () => { mounted.current = false; ids.clear(); document.removeEventListener("visibilitychange", update); };
  }, []);
  const remove = useCallback((id: string) => setEntries(items => items.filter(item => item.id !== id)), []);
  const dismiss = useCallback((id: string) => { activeIds.current.delete(id); setEntries(items => items.map(item => item.id === id ? { ...item, closing: true } : item)); }, []);
  const dismissAll = useCallback(() => { activeIds.current.clear(); setEntries(items => items.map(item => ({ ...item, closing: true }))); }, []);
  const show = useCallback((options: ToastOptions) => {
    const id = `tt-toast-${++nextId.current}`;
    const entry: Entry = { ...options, id, revision: 0, position: options.position ?? "top-right",
      duration: durationFor(options),
      trigger: document.activeElement instanceof HTMLElement ? document.activeElement : null };
    activeIds.current.add(id);
    setEntries(items => [entry, ...items]);
    setAnnouncement({ text: [options.title, options.description].filter(Boolean).join(". "), tone: options.tone ?? "neutral" });
    return id;
  }, []);
  const promiseToast = useCallback(<T,>(task: Promise<T> | (() => Promise<T>), options: ToastPromiseOptions<T>): ToastPromiseResult<T> => {
    const id = show({ ...messageOptions(options.loading), position: options.position, loading: true });
    const settle = (message: ToastMessage, tone: UiTone) => {
      if (!mounted.current || !activeIds.current.has(id)) return;
      const next = { ...messageOptions(message), tone, loading: false };
      setEntries(items => items.map(item => item.id === id && !item.closing ? {
        ...next, id, position: item.position, trigger: item.trigger, revision: item.revision + 1,
        duration: durationFor({ ...next, duration: next.duration ?? options.duration }),
      } : item));
      setAnnouncement({ text: [next.title, next.description].filter(Boolean).join(". "), tone });
    };
    const promise = Promise.resolve().then(() => typeof task === "function" ? task() : task).then(value => {
      let message: ToastMessage;
      try { message = typeof options.success === "function" ? options.success(value) : options.success; }
      catch { message = "Proses selesai."; }
      settle(message, "success"); return value;
    }, error => {
      let message: ToastMessage;
      try { message = typeof options.error === "function" ? options.error(error) : options.error; }
      catch { message = "Proses gagal. Silakan coba lagi."; }
      settle(message, "error"); throw error;
    });
    void promise.catch(() => {});
    return { id, promise };
  }, [show]);
  const api = useMemo(() => ({ show, promiseToast, dismiss, dismissAll }), [show, promiseToast, dismiss, dismissAll]);
  return <ToastContext.Provider value={api}>
    {children}
    <div className="sr-only" role="status" aria-atomic="true">{announcement.tone !== "error" && announcement.text}</div>
    <div className="sr-only" role="alert" aria-atomic="true">{announcement.tone === "error" && announcement.text}</div>
    {positions.filter(position => entries.some(item => item.position === position)).map(position => <ToastStack key={position} position={position} entries={entries.filter(item => item.position === position)}
      layout={layout} paused={hidden} dismiss={remove} onClosing={id => activeIds.current.delete(id)} />)}
  </ToastContext.Provider>;
}

function ToastStack({ entries, position, layout, paused, dismiss, onClosing }: {
  entries: Entry[]; position: ToastPosition; layout: "stacked" | "expanded"; paused: boolean; dismiss: (id: string) => void;
  onClosing: (id: string) => void;
}) {
  const [hovered, setHovered] = useState(false);
  const [focused, setFocused] = useState(false);
  const [pinned, setPinned] = useState(false);
  const list = useRef<HTMLOListElement>(null);
  const [heights, setHeights] = useState<Record<string, number>>({});
  const ids = entries.map(entry => entry.id).join(",");
  useEffect(() => {
    const items = list.current?.querySelectorAll<HTMLElement>(".tt-toast-item");
    if (!items) return;
    const observer = new ResizeObserver(() => {
      const next = Object.fromEntries(Array.from(items, item => [item.dataset.id!, item.offsetHeight]));
      setHeights(previous => JSON.stringify(previous) === JSON.stringify(next) ? previous : next);
    });
    items.forEach(item => observer.observe(item));
    return () => observer.disconnect();
  }, [ids]);
  const expanded = layout === "expanded" || hovered || focused || pinned;
  const offsets = entries.map((_, index) => entries.slice(0, index).reduce((sum, entry) => sum + (heights[entry.id] ?? 90) + 12, 0));
  const totalHeight = entries.reduce((sum, entry) => sum + (heights[entry.id] ?? 90) + 12, 0);
  const height = expanded ? Math.max(0, totalHeight - 12) : (heights[entries[0]?.id] ?? 90) + Math.min(entries.length - 1, 2) * 8;
  const [vertical, horizontal] = position.split("-") as ["top" | "bottom", "left" | "center" | "right"];
  if (!entries.length) return null;
  return <section aria-label={`Notifikasi ${position}`} className={cx("tt-toasts group/stack pointer-events-none fixed z-[1100] flex w-[min(22rem,calc(100vw-2rem))] min-w-0 max-w-[calc(100vw-2rem)] gap-2 p-0",vertical==='top'?"top-[max(1rem,env(safe-area-inset-top))] flex-col":"bottom-[max(1rem,env(safe-area-inset-bottom))] flex-col-reverse [--tt-toast-enter-y:10px]",horizontal==='left'?"start-[max(1rem,env(safe-area-inset-left))]":horizontal==='right'?"end-[max(1rem,env(safe-area-inset-right))]":"start-1/2 -translate-x-1/2")}
    data-position={position} data-expanded={expanded}
    onMouseEnter={() => setHovered(true)} onMouseLeave={() => setHovered(false)}
    onFocusCapture={() => setFocused(true)} onBlurCapture={event => { if (!event.currentTarget.contains(event.relatedTarget)) setFocused(false); }}>
    {entries.length > 1 && layout === "stacked" && <Button size="sm" variant="ghost" className="pointer-events-auto w-auto self-end bg-surface" aria-expanded={expanded}
      aria-label={pinned ? "Tumpuk notifikasi" : `Bentangkan ${entries.length} notifikasi`}
      onClick={() => setPinned(value => !value)}>{pinned ? "Tumpuk" : `${entries.length} notifikasi`}</Button>}
    <ol ref={list} className="relative m-0 flex-none list-none p-0 transition-[height] duration-220 ease-[cubic-bezier(.2,0,0,1)] group-data-[expanded=true]/stack:max-h-[calc(100dvh-7rem)] group-data-[expanded=true]/stack:overflow-x-hidden group-data-[expanded=true]/stack:overflow-y-auto motion-reduce:transition-none" style={{ height }}>
      {entries.map((entry, index) => <Toast key={entry.id} entry={entry} obscured={!expanded && index > 0}
        style={{ "--tt-toast-offset": `${expanded ? offsets[index] : Math.min(index, 2) * 8}px`, "--tt-toast-scale": expanded ? 1 : 1 - Math.min(index, 2) * 0.03, zIndex: entries.length - index } as CSSProperties}
        paused={paused || hovered || focused || (!expanded && index > 0)} dismiss={dismiss} onClosing={onClosing} />)}
    </ol>
  </section>;
}

function Toast({ entry, paused, obscured, dismiss, style, onClosing }: { entry: Entry; paused: boolean; obscured: boolean; dismiss: (id: string) => void; style: CSSProperties; onClosing: (id: string) => void }) {
  const [localClosing, setClosing] = useState(false);
  const closing = localClosing || Boolean(entry.closing);
  const remaining = useRef(entry.duration);
  const element = useRef<HTMLLIElement>(null);
  const [actionBusy, setActionBusy] = useState(false);
  const [actionError, setActionError] = useState(false);
  const actionLock = useRef(false);
  const alive = useRef(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  const close = useCallback(() => {
    onClosing(entry.id);
    if (element.current?.contains(document.activeElement) && entry.trigger?.isConnected) entry.trigger.focus();
    setClosing(true);
  }, [entry.trigger, entry.id, onClosing]);
  useEffect(() => { remaining.current = entry.duration; }, [entry.revision, entry.duration]);
  useEffect(() => {
    if (paused || closing || entry.loading || actionBusy || actionError || entry.duration === 0) return;
    const started = Date.now();
    const timer = setTimeout(close, remaining.current);
    return () => { clearTimeout(timer); remaining.current = Math.max(0, remaining.current - (Date.now() - started)); };
  }, [paused, closing, entry.duration, entry.revision, entry.loading, actionBusy, actionError, close]);
  useEffect(() => {
    if (!closing) return;
    const timer = setTimeout(() => dismiss(entry.id), window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 200);
    return () => clearTimeout(timer);
  }, [closing, dismiss, entry.id]);
  return <li ref={element} style={style} data-id={entry.id} className="tt-toast-item group/item pointer-events-auto absolute start-0 top-0 w-full min-w-0 origin-top [transform:translateY(var(--tt-toast-offset))_scale(var(--tt-toast-scale))] transition-transform duration-220 ease-[cubic-bezier(.2,0,0,1)] group-data-[position^=bottom]/stack:top-auto group-data-[position^=bottom]/stack:bottom-0 group-data-[position^=bottom]/stack:origin-bottom group-data-[position^=bottom]/stack:[transform:translateY(calc(-1*var(--tt-toast-offset)))_scale(var(--tt-toast-scale))] group-data-[expanded=false]/stack:[&:nth-child(n+4)]:invisible inert:pointer-events-none motion-reduce:transition-none" data-closing={closing} inert={obscured || closing} aria-hidden={obscured || undefined}>
    <div className="relative box-border w-full animate-[tt-toast-enter_200ms_ease-out_both] rounded-lg border border-line bg-surface text-foreground shadow-[0_4px_14px_rgb(0_0_0/0.08)] group-data-[closing=true]/item:animate-[tt-toast-exit_200ms_ease-in_both] motion-reduce:animate-none" data-tone={entry.tone ?? "neutral"} aria-busy={entry.loading || actionBusy || undefined}>
      <div className="py-4 ps-3.5 pe-12 wrap-anywhere">
        <div className="flex items-start gap-2">
          {entry.loading ? <Spinner size="sm" decorative className="mt-px flex-none text-muted" /> : entry.tone && entry.tone !== "neutral" && <svg className={cx("mt-px flex-none",{info:"text-accent",success:"text-(--success)",warning:"text-warning-solid",error:"text-danger"}[entry.tone])} aria-hidden="true" viewBox="0 0 24 24" width="18" height="18">
            {entry.tone === "warning" ? <path fill="currentColor" d="M10.3 3.9a2 2 0 0 1 3.4 0l8 14A2 2 0 0 1 20 21H4a2 2 0 0 1-1.7-3.1Z" /> : <circle fill="currentColor" cx="12" cy="12" r="10" />}
            <g stroke="var(--surface)" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round">
              {entry.tone === "success" ? <path d="m7 12 3 3 7-7" /> : entry.tone === "error" ? <path d="m8 8 8 8m0-8-8 8" /> : <path d="M12 10v6m0-9v.01" />}
            </g>
          </svg>}
          <p className="min-w-0 text-[13px]/normal font-medium text-foreground">{entry.title}</p>
        </div>
        <div className="text-xs/normal text-muted not-empty:mt-1 data-[icon=true]:ps-6.5" data-icon={Boolean(entry.loading || (entry.tone && entry.tone !== "neutral"))}>
        {entry.description && <p>{entry.description}</p>}
        {entry.content}
        {entry.action && <div className="mt-3"><Button size="sm" loading={actionBusy} disabled={entry.loading} onClick={async () => {
          if (actionLock.current) return;
          actionLock.current = true; setActionBusy(true); setActionError(false);
          try {
            await entry.action?.onClick();
            if (alive.current && entry.action?.closeOnClick !== false) close();
          } catch { if (alive.current) setActionError(true); }
          finally { actionLock.current = false; if (alive.current) setActionBusy(false); }
        }}>{entry.action.label}</Button></div>}
        {actionError && <p role="alert" className="mt-2">Aksi belum berhasil. Silakan coba lagi.</p>}
        </div>
      </div>
      <Button size="sm" variant="ghost" className="absolute end-0.5 top-0.5 size-11 min-w-11 rounded-full border-0 bg-transparent p-0 text-muted shadow-none before:pointer-events-none before:absolute before:inset-2 before:rounded-full before:bg-transparent hover:before:bg-surface-alt focus-visible:before:bg-surface-alt active:before:bg-line [&>svg]:relative [&>svg]:size-3.5" aria-label={`Tutup notifikasi: ${entry.title}`} onClick={close}>
        <svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m6 6 12 12M18 6 6 18" /></svg>
      </Button>
    </div>
  </li>;
}
