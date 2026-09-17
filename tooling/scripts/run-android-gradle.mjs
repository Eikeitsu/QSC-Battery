#!/usr/bin/env node
/**
 * Cross-platform: run apps/android/gradlew with given args.
 * Usage: node tooling/scripts/run-android-gradle.mjs spotlessCheck
 */
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const android = join(root, "apps", "android");
const isWin = process.platform === "win32";
const gradlew = join(android, isWin ? "gradlew.bat" : "gradlew");

if (!existsSync(gradlew)) {
  console.error(`[run-android-gradle] missing ${gradlew}`);
  process.exit(1);
}

const args = process.argv.slice(2);
if (args.length === 0) {
  console.error("usage: node tooling/scripts/run-android-gradle.mjs <gradle-task>...");
  process.exit(1);
}

const r = spawnSync(gradlew, args, {
  cwd: android,
  stdio: "inherit",
  shell: isWin,
  env: process.env,
});
process.exit(r.status ?? 1);
