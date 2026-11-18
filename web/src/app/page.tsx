import Image from "next/image";
import { NavigationLink as Link } from "@/components/ui/navigation-progress";
import { StarterPreview } from "@/components/starter-preview";
import { ThemeSelect } from "@/components/ui/theme-select";
import { textLink } from "@/components/ui/styles";

export default function Home() {
  return (
    <main id="konten" className="tt-starter mx-auto max-w-7xl px-4 py-6 sm:px-7 sm:py-8" tabIndex={-1}>
      <header className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <Image src="/logo.png" alt="" width={36} height={40} priority />
          <div>
            <h1>TonzToon Admin</h1>
            <p className="mt-1 text-sm text-muted">Pemeriksaan komponen</p>
          </div>
        </div>
        <ThemeSelect />
      </header>
      <p className="mt-6 max-w-2xl text-muted">
        Contoh lokal untuk memeriksa komponen, varian, dan state bersama sebelum
        migrasi halaman admin. Tidak terhubung ke backend.
      </p>
      <StarterPreview />
      <Link href="/overview" className={textLink}>Buka Overview frontend contoh</Link>
      <noscript>Aktifkan JavaScript untuk memeriksa interaksi komponen dan mengganti tema.</noscript>
    </main>
  );
}
