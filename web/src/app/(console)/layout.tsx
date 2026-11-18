import type { ReactNode } from "react";
import { AdminShell } from "@/components/admin/shell";
import { isFrontendDemoEnabled } from "@/lib/server/demo-mode";
import { connection } from "next/server";
import { Suspense } from "react";
import Link from "next/link";
async function Console({children}:{children:ReactNode}) {
  await connection();
  if (!isFrontendDemoEnabled()) return <main id="konten" className="mx-auto max-w-3xl p-8"><h1 className="mb-4 text-2xl">Frontend admin belum dihubungkan</h1><p>Mode contoh dinonaktifkan. Integrasi sesi dan API produksi diselesaikan pada fase 3.</p><Link className="mt-4 inline-flex min-h-11 items-center underline" href="/">Pemeriksaan komponen</Link></main>;
  return <AdminShell>{children}</AdminShell>;
}
export default function ConsoleLayout({children}:{children:ReactNode}) {
  return <Suspense fallback={<main id="konten" className="p-8">Memuat konsol admin…</main>}><Console>{children}</Console></Suspense>;
}
