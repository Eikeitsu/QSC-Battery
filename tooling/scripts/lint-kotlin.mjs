#!/usr/bin/env node
/**
 * Spotless / ktlint for apps/android（*.kt / *.gradle.kts）。
 * --fix → spotlessApply；否则 spotlessCheck。
 * 本机无 JDK / gradlew 失败时跳过；CI / REQUIRE_KOTLIN_LINT=1 则失败。
 */
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const fix = process.argv.includes("--fix");
const requireKotlin =
  process.env.CI === "true" || process.env.REQUIRE_KOTLIN_LINT === "1";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const android = join(root, "apps", "android");
const isWin = process.platform === "win32";
const gradlew = join(android, isWin ? "gradlew.bat" : "gradlew");

if (!existsSync(gradlew)) {
  const msg = `[lint:kotlin] missing ${gradlew}`;
  if (requireKotlin) {
    console.error(msg);
    process.exit(1);
  }
  console.log(`${msg} — skip`);
  process.exit(0);
}

const java = spawnSync("java", ["-version"], { encoding: "utf8" });
if (java.error?.code === "ENOENT") {
  const msg = "[lint:kotlin] java not installed";
  if (requireKotlin) {
    console.error(msg);
    process.exit(1);
  }
  console.log(`${msg} — skip`);
  process.exit(0);
}

const task = fix ? "spotlessApply" : "spotlessCheck";
const r = spawnSync(gradlew, [task, "--quiet"], {
  cwd: android,
  stdio: "inherit",
  shell: isWin,
  env: process.env,
});

if ((r.status ?? 1) !== 0) {
  if (requireKotlin) process.exit(r.status ?? 1);
  console.log(`[lint:kotlin] ${task} failed — skip (set REQUIRE_KOTLIN_LINT=1 to fail)`);
  process.exit(0);
}
process.exit(0);
