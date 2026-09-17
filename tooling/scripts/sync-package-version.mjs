#!/usr/bin/env node
/**
 * Sync root package.json version from module/module.prop display version.
 * npm version is metadata only; Magisk display version remains module.prop.
 *
 * Mapping: 2026.09.16 → 20260916.0.0 ; 2026.09.16.2 → 20260916.2.0
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const prop = readFileSync(join(root, "module/module.prop"), "utf8");
const pkgPath = join(root, "package.json");
const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));

const verLine = prop.match(/^version=(.+)$/m)?.[1]?.trim();
if (!verLine) {
  console.error("[sync-package-version] no version= in module.prop");
  process.exit(1);
}

const parts = verLine.split(".").map((p) => p.replace(/\D/g, "")).filter(Boolean);
let mapped;
if (parts.length >= 3) {
  const y = parts[0].padStart(4, "0");
  const m = parts[1].padStart(2, "0");
  const d = parts[2].padStart(2, "0");
  const rev = parts[3] || "0";
  mapped = `${y}${m}${d}.${rev}.0`;
} else {
  mapped = `${verLine.replace(/\D/g, "") || "0"}.0.0`;
}

if (pkg.version === mapped) {
  console.log(`[sync-package-version] already ${mapped}`);
  process.exit(0);
}
pkg.version = mapped;
writeFileSync(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`, "utf8");
console.log(`[sync-package-version] ${verLine} → package.json ${mapped}`);
