#!/usr/bin/env node
/**
 * clang-format check/fix for native/** when present.
 */
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const fix = process.argv.includes("--fix");
const requireClang =
  process.env.CI === "true" || process.env.REQUIRE_CLANG_FORMAT === "1";

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (/\.(c|cc|cpp|h|hpp)$/i.test(name)) out.push(p);
  }
  return out;
}

const files = walk("native");
if (!files.length) {
  console.log("[lint:clang] no native C/C++ sources — skip");
  process.exit(0);
}

const which = spawnSync(
  process.platform === "win32" ? "where" : "which",
  ["clang-format"],
  {
    encoding: "utf8",
  },
);
if (which.status !== 0) {
  const msg = "[lint:clang] clang-format not installed";
  if (requireClang) {
    console.error(msg);
    process.exit(1);
  }
  console.log(`${msg} — skip`);
  process.exit(0);
}

const args = fix ? ["-i", ...files] : ["--dry-run", "-Werror", ...files];
const r = spawnSync("clang-format", args, { encoding: "utf8", stdio: "inherit" });
process.exit(r.status ?? 1);
