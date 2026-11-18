import { Suspense } from "react";
import { notFound } from "next/navigation";
import { parseDataRoute } from "@/lib/admin-data/routes";
import { DataPage } from "@/components/admin/data-page";
import { PageSkeleton } from "@/components/admin/page-skeleton";
async function Content({ params }: { params: Promise<{ segments: string[] }> }) {
  const { segments } = await params, route = parseDataRoute(segments);
  if (!route) notFound();
  return <DataPage key={segments.join("/")} route={route} />;
}
export default function Page(props: { params: Promise<{ segments: string[] }> }) { return <Suspense fallback={<PageSkeleton variant="detail" />}><Content {...props} /></Suspense>; }
