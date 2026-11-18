import { cx } from "./types";

export function Skeleton({ className }: { className?: string }) {
  return <span aria-hidden="true" className={cx("relative block min-w-0 max-w-full overflow-hidden rounded-control bg-line before:absolute before:inset-0 before:-translate-x-full before:bg-[linear-gradient(90deg,transparent,var(--surface),transparent)] motion-safe:before:animate-[tt-skeleton-shimmer_1.5s_ease-in-out_infinite]", className)} />;
}
