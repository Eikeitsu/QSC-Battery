import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(root, "..");

export default defineConfig({
  root,
  base: "./",
  plugins: [vue()],
  build: {
    outDir: resolve(repoRoot, ".build/webroot"),
    emptyOutDir: true,
    assetsDir: "assets",
    cssCodeSplit: false,
    rollupOptions: {
      output: {
        entryFileNames: "js/app.js",
        chunkFileNames: "js/[name].js",
        assetFileNames: (info) => {
          if (info.name?.endsWith(".css")) return "css/style.css";
          return "assets/[name][extname]";
        },
      },
    },
  },
  server: {
    port: 5173,
    host: true,
  },
});
