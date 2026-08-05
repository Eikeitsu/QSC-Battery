#!/usr/bin/env node
/**
 * 构建 WebUI：Vite 打包 Vue 3 + Vant（TypeScript）→ .build/webroot，并同步到 module/webroot。
 * 旧版原生源码归档在 archives/webroot-vanilla-202607/，勿覆盖归档。
 */
import { execSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, rmSync, readdirSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const outDir = join(repoRoot, ".build", "webroot");
const moduleWeb = join(repoRoot, "module", "webroot");

function log(msg) {
  console.log(`[build-web] ${msg}`);
}

log("vite build…");
execSync("npx vite build --config webui/vite.config.ts", {
  cwd: repoRoot,
  stdio: "inherit",
});

if (!existsSync(outDir)) {
  throw new Error("missing .build/webroot after vite build");
}

log("sync → module/webroot");
rmSync(moduleWeb, { recursive: true, force: true });
mkdirSync(moduleWeb, { recursive: true });
cpSync(outDir, moduleWeb, { recursive: true });

const files = [];
function walk(dir, prefix = "") {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) walk(join(dir, entry.name), rel);
    else files.push(rel);
  }
}
walk(outDir);
log(`output -> ${outDir} (${files.length} files)`);
log("done");
