import { Suspense } from "react";
import { DataFlowViewer } from "@/components/data-flow/viewer";
import { PageSkeleton } from "@/components/admin/page-skeleton";
export default function Page() { return <Suspense fallback={<PageSkeleton variant="detail"/>}><DataFlowViewer/></Suspense>; }
