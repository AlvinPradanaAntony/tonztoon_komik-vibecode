"use client";

import NextLink, { useLinkStatus } from "next/link";
import { createContext, useCallback, useContext, useEffect, useId, useState, type ComponentProps, type ReactNode } from "react";

const NavigationContext = createContext<(id: string, pending: boolean) => void>(() => {});

export function NavigationProgressProvider({ children }: { children: ReactNode }) {
  const [pendingLinks, setPendingLinks] = useState<Set<string>>(() => new Set());
  const update = useCallback((id: string, pending: boolean) => {
    setPendingLinks(current => {
      if (current.has(id) === pending) return current;
      const next = new Set(current);
      if (pending) next.add(id); else next.delete(id);
      return next;
    });
  }, []);

  return <NavigationContext.Provider value={update}>
    {pendingLinks.size > 0 && <div role="progressbar" aria-label="Memuat halaman" className="tt-navigation-progress pointer-events-none fixed inset-x-0 top-0 z-[100] h-[3px] overflow-hidden bg-accent/15">
      <span className="block h-full w-1/3 origin-left bg-accent motion-safe:animate-[tt-navigation-progress_1.2s_ease-in-out_infinite]" />
    </div>}
    {children}
  </NavigationContext.Provider>;
}

function LinkPending() {
  const { pending } = useLinkStatus();
  const update = useContext(NavigationContext);
  const id = useId();
  useEffect(() => {
    if (!pending) return;
    update(id, true);
    return () => update(id, false);
  }, [id, pending, update]);
  return null;
}

/** Preserve Next.js link behavior while reporting its native pending lifecycle. */
export function NavigationLink({ children, ...props }: ComponentProps<typeof NextLink>) {
  return <NextLink {...props}>{children}<LinkPending /></NextLink>;
}
