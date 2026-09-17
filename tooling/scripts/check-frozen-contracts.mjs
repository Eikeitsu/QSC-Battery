#!/usr/bin/env node
/**
 * Guard frozen Magisk / APP contracts (Phase 0 optional CI check).
 */
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

function read(rel) {
  return readFileSync(join(root, rel), "utf8");
}

const prop = read("module/module.prop");
if (!/^id=QSC_Battery$/m.test(prop)) {
  throw new Error("module.prop id must be QSC_Battery");
}

const gradle = read("apps/android/build.gradle.kts");
if (!/applicationId\s*=\s*"com\.qsc\.battery"/.test(gradle)) {
  throw new Error('apps/android applicationId must be "com.qsc.battery"');
}
if (!/namespace\s*=\s*"com\.qsc\.battery"/.test(gradle)) {
  throw new Error('apps/android namespace must be "com.qsc.battery"');
}

for (const entry of [
  "module/service.sh",
  "module/customize.sh",
  "module/uninstall.sh",
  "module/action.sh",
  "module/module.prop",
]) {
  read(entry); // exists + readable
}

console.log("[check-frozen-contracts] ok");
