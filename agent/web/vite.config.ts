import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Build artefacts are emitted into ../static so FastAPI can mount them.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: "../static",
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    proxy: {
      "/chat": { target: "http://localhost:8080", changeOrigin: true },
      "/healthz": "http://localhost:8080",
      "/readyz": "http://localhost:8080",
    },
  },
});
