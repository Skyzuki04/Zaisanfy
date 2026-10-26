import type { Metadata } from "next";
import "./globals.css";
import { SITE_URL } from "@/lib/site";
import SiteHeader from "@/components/SiteHeader";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Zaisanfy · Propiedades con recorrido 360",
  description: "Encuentra propiedades con recorridos 360 e inspírate con creativos.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body>
        <SiteHeader />
        {children}
      </body>
    </html>
  );
}
