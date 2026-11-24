import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// App 3 del SRS: Núcleo Administrativo (admin-core.zaisanfy.com). Puerto 5174 para no chocar con la Consola.
export default defineConfig({
  plugins: [react()],
  server: { port: 5174, strictPort: true },
  preview: { port: 5174 },
});
