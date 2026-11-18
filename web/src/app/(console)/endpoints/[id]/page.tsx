import { Suspense } from "react";
import { MonitoringPage } from "@/components/admin/monitoring-page";
import { PageSkeleton } from "@/components/admin/page-skeleton";
async function Detail({params}:{params:Promise<{id:string}>}) {const {id}=await params;return <MonitoringPage kind="endpoints" id={id}/>;}
export default function Page(props:{params:Promise<{id:string}>}){return <Suspense fallback={<PageSkeleton variant="detail" />}><Detail {...props}/></Suspense>;}
