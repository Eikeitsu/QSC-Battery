#!/usr/bin/env node
/** Spawn python3/python with remaining argv. Exit with child status. */
import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
if (!args.length) {
  console.error("usage: run-python.mjs <script.py> [args...]");
  process.exit(2);
}

const bins =
  process.platform === "win32" ? ["python", "py", "python3"] : ["python3", "python"];

for (const bin of bins) {
  const r = spawnSync(bin, args, { stdio: "inherit" });
  if (r.error?.code === "ENOENT") continue;
  process.exit(r.status ?? 1);
}

console.error("python not found (tried: " + bins.join(", ") + ")");
process.exit(1);
