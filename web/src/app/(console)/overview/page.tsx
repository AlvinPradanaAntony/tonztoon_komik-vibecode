import { Suspense } from "react";
import { Overview } from "@/components/admin/overview";
import { PageSkeleton } from "@/components/admin/page-skeleton";
export const metadata = { title: "Overview · TonzToon Admin" };
export default function Page() { return <Suspense fallback={<PageSkeleton variant="overview" />}><Overview/></Suspense>; }
