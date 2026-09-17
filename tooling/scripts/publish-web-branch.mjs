#!/usr/bin/env node
import { execFileSync, execSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const builtWeb = join(repoRoot, ".build", "webroot");
const publishDir = join(repoRoot, ".build", "dist-web-publish");
const branch = "dist-web";

if (!existsSync(builtWeb)) {
  console.error("[publish-web-branch] missing .build/webroot");
  process.exit(1);
}

const repo = process.env.GITHUB_REPOSITORY;
const token = process.env.GITHUB_TOKEN;
if (!repo || !token) {
  console.log("[publish-web-branch] skip push (GITHUB_REPOSITORY/GITHUB_TOKEN not set)");
  process.exit(0);
}

rmSync(publishDir, { recursive: true, force: true });
mkdirSync(publishDir, { recursive: true });
cpSync(builtWeb, publishDir, { recursive: true });
writeFileSync(
  join(publishDir, "README.md"),
  "# Built apps/webui\n\nCI 自动发布：构建后的 webroot。历史提交保留（非 force-push）。\n",
);
const sha = process.env.GITHUB_SHA || "";
if (sha) {
  writeFileSync(join(publishDir, "SOURCE_SHA"), `${sha}\n`);
}

const script = join(repoRoot, "tooling", "scripts", "git-push-tree.sh");
execSync(`chmod +x ${JSON.stringify(script)}`, { cwd: repoRoot, stdio: "inherit" });
execFileSync("bash", [script, branch, publishDir, "dist-web: publish built webroot"], {
  cwd: repoRoot,
  stdio: "inherit",
  env: process.env,
});
console.log(`[publish-web-branch] pushed ${branch}`);
