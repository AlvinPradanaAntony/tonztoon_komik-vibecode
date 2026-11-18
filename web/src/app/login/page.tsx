import { Suspense } from "react";
import { connection } from "next/server";
import { LoginForm } from "@/components/admin/login-form";
import { isFrontendDemoEnabled } from "@/lib/server/demo-mode";
async function Content() { await connection(); return <LoginForm enabled={isFrontendDemoEnabled()} />; }
export default function Page() { return <Suspense fallback={<main id="konten" className="p-8">Memuat login…</main>}><Content /></Suspense>; }
