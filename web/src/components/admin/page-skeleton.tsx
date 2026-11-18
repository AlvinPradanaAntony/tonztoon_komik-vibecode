import { Skeleton } from "@/components/ui/skeleton";

export function PageSkeleton({ variant = "list" }: { variant?: "overview" | "list" | "detail" }) {
  return <div className="tt-page-skeleton grid min-w-0 grid-cols-1 gap-6" data-variant={variant} aria-busy="true" aria-label="Konten halaman sedang dimuat">
    <p className="sr-only" role="status">Memuat konten halaman…</p>
    <div className="grid min-w-0 grid-cols-1 gap-3" aria-hidden="true">
      <Skeleton className="h-8 w-48 max-w-full" />
      <Skeleton className="h-4 w-80 max-w-[85%]" />
    </div>
    {variant === "overview" ? <>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4" aria-hidden="true">
        {[0, 1, 2, 3].map(key => <div key={key} className="grid min-w-0 grid-cols-1 gap-5 rounded-panel bg-panel p-5">
          <Skeleton className="h-4 w-3/4" /><Skeleton className="h-8 w-1/2" /><Skeleton className="h-3 w-2/3" />
        </div>)}
      </div>
      <div className="grid min-w-0 grid-cols-1 gap-5 rounded-panel bg-panel p-5 sm:p-6" aria-hidden="true">
        <Skeleton className="h-5 w-48 max-w-[75%]" /><Skeleton className="h-64 w-full rounded-inner" />
      </div>
    </> : <div className="grid min-w-0 grid-cols-1 gap-6 rounded-panel bg-panel p-5 sm:p-6" aria-hidden="true">
      <Skeleton className="h-5 w-48 max-w-[75%]" />
      {variant === "list" ? <>
        <Skeleton className="h-11 w-80 max-w-full" />
        <div className="grid min-w-0 grid-cols-1 gap-5 rounded-inner bg-surface p-4">
          {[0, 1, 2, 3, 4].map(key => <div key={key} className="flex min-w-0 items-center gap-5">
            <Skeleton className="h-4 w-1/2" /><Skeleton className="ms-auto h-4 w-1/6" /><Skeleton className="h-4 w-1/6" />
          </div>)}
        </div>
      </> : <div className="grid min-w-0 grid-cols-1 gap-6 rounded-inner bg-surface p-5">
        {[0, 1, 2, 3].map(key => <div key={key} className="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-[1fr_2fr]">
          <Skeleton className="h-4 w-28 max-w-full" /><Skeleton className="h-4 w-3/4" />
        </div>)}
      </div>}
    </div>}
  </div>;
}
