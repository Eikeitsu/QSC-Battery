import { defineConfig } from "vitest/config";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  root,
  resolve: {
    alias: {
      "@": resolve(root, "src"),
    },
  },
  test: {
    name: "webui",
    environment: "node",
    dir: resolve(root, "test"),
    include: ["unit/**/*.{test,spec}.ts"],
    reporters: ["default"],
  },
});
