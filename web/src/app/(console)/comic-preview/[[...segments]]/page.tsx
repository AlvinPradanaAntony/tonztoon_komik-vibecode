import { Suspense } from "react";
import { notFound } from "next/navigation";
import { ComicPreview } from "@/components/admin/comic-preview";
import { PageSkeleton } from "@/components/admin/page-skeleton";
async function Content({ params }: { params: Promise<{ segments?: string[] }> }) {
  const { segments = [] } = await params;
  if (![0, 2, 4].includes(segments.length) || segments.length === 4 && segments[2] !== "chapters") notFound();
  return <ComicPreview source={segments[0]} slug={segments[1]} chapter={segments[3]}/>;
}
export default function Page(props: { params: Promise<{ segments?: string[] }> }) { return <Suspense fallback={<PageSkeleton variant="detail" />}><Content {...props}/></Suspense>; }
