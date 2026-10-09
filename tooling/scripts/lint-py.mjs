#!/usr/bin/env node
/**
 * Format / check Python under tooling/scripts with ruff when available.
 * Prefers `python -m ruff`, then `ruff` on PATH.
 * CI: REQUIRE_RUFF=1 fails if ruff missing.
 */
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const fix = process.argv.includes("--fix");
const requireRuff = process.env.CI === "true" || process.env.REQUIRE_RUFF === "1";

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (name.endsWith(".py")) out.push(p);
  }
  return out;
}

/** @returns {((args: string[]) => number) | null} */
function resolveRuff() {
  for (const py of ["python3", "python"]) {
    const probe = spawnSync(py, ["-c", "import ruff"], { encoding: "utf8" });
    if (probe.error?.code === "ENOENT") continue;
    if (probe.status === 0) {
      return (args) => {
        const r = spawnSync(py, ["-m", "ruff", ...args], {
          encoding: "utf8",
          stdio: "inherit",
        });
        return r.status ?? 1;
      };
    }
  }
  const binProbe = spawnSync("ruff", ["--version"], { encoding: "utf8" });
  if (binProbe.error?.code === "ENOENT") return null;
  if (binProbe.status === 0) {
    return (args) => {
      const r = spawnSync("ruff", args, { encoding: "utf8", stdio: "inherit" });
      return r.status ?? 1;
    };
  }
  return null;
}

const files = walk("tooling/scripts").filter((f) => f.endsWith(".py"));
if (!files.length) {
  console.log("[lint:py] no python files");
  process.exit(0);
}

const runRuff = resolveRuff();
if (!runRuff) {
  const msg = "[lint:py] ruff not installed";
  if (requireRuff) {
    console.error(msg);
    process.exit(1);
  }
  console.log(`${msg} — skip (pip install ruff)`);
  process.exit(0);
}

const checkArgs = fix ? ["check", "--fix", ...files] : ["check", ...files];
const checkStatus = runRuff(checkArgs);
if (checkStatus !== 0) process.exit(checkStatus);

const fmtArgs = fix ? ["format", ...files] : ["format", "--check", ...files];
process.exit(runRuff(fmtArgs));
