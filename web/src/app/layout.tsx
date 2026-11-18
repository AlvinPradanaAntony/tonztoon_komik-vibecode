import type { Metadata } from "next";
import "./globals.css";
import { ToastProvider } from "@/components/ui/toast";
import { NavigationProgressProvider } from "@/components/ui/navigation-progress";

export const metadata: Metadata = {
  title: "TonzToon Admin",
  description: "Konsol operasional TonzToon. Frontend fase 2, integrasi backend belum diaktifkan.",
  robots: { index: false, follow: false },
  icons: { icon: "/logo.png", apple: "/logo.png" },
};

const themeBootstrap = `try{var theme=localStorage.getItem("tt-admin-theme");if(theme==="light"||theme==="dark"){document.documentElement.dataset.theme=theme;}}catch{}`;

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="id" suppressHydrationWarning>
      <head>
        <meta name="color-scheme" content="light dark" />
        <script dangerouslySetInnerHTML={{ __html: themeBootstrap }} />
      </head>
      <body className="min-h-dvh bg-page font-sans antialiased has-[.tt-starter]:bg-canvas">
        <a href="#konten" className="absolute start-2 top-2 z-50 -translate-y-[200%] bg-surface p-3 text-foreground focus:translate-y-0">Lewati ke konten</a>
        <NavigationProgressProvider><ToastProvider>{children}</ToastProvider></NavigationProgressProvider>
      </body>
    </html>
  );
}
