import { isFrontendDemoEnabled } from "@/lib/server/demo-mode";
import { connection } from "next/server";
export async function GET(_request: Request, { params }: { params: Promise<{ scenario: string }> }) {
  await connection();
  if (!isFrontendDemoEnabled()) return new Response(null, { status: 404 });
  const { scenario } = await params;
  const headers = { "Cache-Control": "private, no-store", "X-Demo-Fixture": "true" };
  if (["403", "404", "413", "503", "504"].includes(scenario)) return new Response("Fixture lokal: HTTP gagal", { status: Number(scenario), headers });
  if (scenario === "html") return new Response("<!doctype html><title>Fixture HTML</title>", { headers: { ...headers, "Content-Type": "text/html" } });
  if (scenario === "corrupt") return new Response(new Uint8Array([0, 1, 2, 3]), { headers: { ...headers, "Content-Type": "image/png" } });
  return new Response(null, { status: 404, headers });
}
