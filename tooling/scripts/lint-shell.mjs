#!/usr/bin/env node
/**
 * Lint Magisk module shell scripts with shellcheck when available.
 * Exit 0 with a skip notice if shellcheck is not installed locally.
 * CI installs shellcheck explicitly so this becomes a hard gate there.
 *
 * Also strips UTF-8 BOM (common on Windows editors) — Magisk/ash + shellcheck
 * both reject BOM before #!.
 */
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
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

function stripUtf8Bom(files) {
  const fixed = [];
  for (const f of files) {
    const buf = readFileSync(f);
    if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) {
      writeFileSync(f, buf.subarray(3));
      fixed.push(f);
      console.warn(`[lint:shell] stripped UTF-8 BOM: ${f}`);
    }
  }
  return fixed;
}

const files = walk("module");
if (!files.length) {
  console.log("[lint:shell] no .sh files");
  process.exit(0);
}

const bomFixed = stripUtf8Bom(files);
if (bomFixed.length && requireShell) {
  console.error(
    "[lint:shell] UTF-8 BOM found in shell scripts (often from Windows editors).",
  );
  console.error(
    "[lint:shell] Cleaned in the runner workspace — commit the BOM-free versions:",
  );
  for (const f of bomFixed) console.error(`  - ${f}`);
  process.exit(1);
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
