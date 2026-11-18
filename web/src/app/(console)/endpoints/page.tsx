import { Suspense } from "react";
import { MonitoringPage } from "@/components/admin/monitoring-page";
import { PageSkeleton } from "@/components/admin/page-skeleton";
export default function Page(){return <Suspense fallback={<PageSkeleton variant="list" />}><MonitoringPage kind="endpoints"/></Suspense>;}
