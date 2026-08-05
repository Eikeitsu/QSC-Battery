#!/usr/bin/env node
/**
 * Lint Magisk module shell scripts with shellcheck when available.
 * Exit 0 with a skip notice if shellcheck is not installed locally.
 * CI installs shellcheck explicitly so this becomes a hard gate there.
 */
import { spawnSync } from "node:child_process";
import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const requireShell = process.env.CI === "true" || process.env.REQUIRE_SHELLCHECK === "1";

function whichShellcheck() {
  const cmd = process.platform === "win32" ? "where" : "which";
  const r = spawnSync(cmd, ["shellcheck"], { encoding: "utf8" });
  return r.status === 0;
}

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (name.endsWith(".sh")) out.push(p);
  }
  return out;
}

const files = walk("module");
if (!files.length) {
  console.log("[lint:shell] no .sh files");
  process.exit(0);
}

if (!whichShellcheck()) {
  if (requireShell) {
    console.error("[lint:shell] shellcheck is required in CI but not found");
    process.exit(1);
  }
  console.warn(
    "[lint:shell] shellcheck not found — skip locally (install shellcheck or rely on CI)",
  );
  process.exit(0);
}

// -x：跟随 source；严重级别 warning；方言与禁用项见仓库根 .shellcheckrc
const r = spawnSync("shellcheck", ["-x", "-S", "warning", ...files], {
  stdio: "inherit",
  shell: process.platform === "win32",
});
process.exit(r.status ?? 1);
