import { Suspense } from "react";
import { ErdExplorer } from "@/components/erd/explorer";
import { PageSkeleton } from "@/components/admin/page-skeleton";
export default function Page() { return <Suspense fallback={<PageSkeleton variant="detail"/>}><ErdExplorer/></Suspense>; }
