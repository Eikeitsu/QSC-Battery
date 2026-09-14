import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import Components from "unplugin-vue-components/vite";
import { VantResolver } from "@vant/auto-import-resolver";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(root, "..");

export default defineConfig({
  root,
  base: "./",
  plugins: [
    {
      name: "qsc-webroot-cache",
      transformIndexHtml(html) {
        if (process.env.NODE_ENV === "production") {
          return html.replace(
            "<head>",
            '<head>\n    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate" />',
          );
        }
        return html;
      },
    },
    vue(),
    Components({
      dts: "components.d.ts",
      resolvers: [VantResolver()],
    }),
  ],
  resolve: {
    alias: {
      "@": resolve(root, "src"),
    },
  },
  build: {
    outDir: resolve(repoRoot, ".build/webroot"),
    emptyOutDir: true,
    assetsDir: "assets",
    cssCodeSplit: false,
    rollupOptions: {
      output: {
        // 固定文件名：Magisk 热更新为「只增改不删」，hash 后缀会留下旧 js/css 并让 index 与资源不一致
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
