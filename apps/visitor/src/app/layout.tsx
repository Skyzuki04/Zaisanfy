import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Zaisanfy",
  description: "Encuentra propiedades con recorridos 360 e inspírate con creativos.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
