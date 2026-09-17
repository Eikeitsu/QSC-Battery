#!/usr/bin/env node
/**
 * Refresh docs/public/app-update.json from apps/android/build.gradle.kts metadata.
 * APK 本体由 GitHub Actions「App」工作流云编译产出，本地默认不 invoke Gradle。
 *
 *   node tooling/scripts/package-app.mjs
 *   node tooling/scripts/package-app.mjs --skip-build   # 同上（保留参数兼容 CI）
 */
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const appRoot = join(repoRoot, "apps", "android");
const releaseDir = join(repoRoot, "release");
const docsPublic = join(repoRoot, "docs", "public");

function log(msg) {
  console.log(`[package-app] ${msg}`);
}

function readGradleVersion() {
  const gradle = readFileSync(join(appRoot, "build.gradle.kts"), "utf8");
  const code = gradle.match(/versionCode\s*=\s*(\d+)/)?.[1] || "0";
  const name = gradle.match(/versionName\s*=\s*"([^"]+)"/)?.[1] || "0.0.0";
  return { versionCode: Number(code), version: name };
}

mkdirSync(releaseDir, { recursive: true });
mkdirSync(docsPublic, { recursive: true });

const { version, versionCode } = readGradleVersion();
const apkCandidates = [
  join(releaseDir, "QSC-Battery.apk"),
  join(appRoot, "build", "outputs", "apk", "release", "app-release.apk"),
  join(appRoot, "build", "outputs", "apk", "debug", "app-debug.apk"),
];
const apk = apkCandidates.find((p) => existsSync(p));
if (apk && apk !== join(releaseDir, "QSC-Battery.apk")) {
  copyFileSync(apk, join(releaseDir, "QSC-Battery.apk"));
  log(`copied ${apk} -> release/QSC-Battery.apk`);
} else if (apk) {
  log(`using existing ${apk}`);
} else {
  log("no local apk (expected: GitHub Actions artifact) — writing app-update.json only");
}

const manifest = {
  version,
  versionCode,
  apkUrl: `https://eikeitsu.github.io/QSC-Battery/releases/QSC-Battery_v${version}.apk`,
  changelog: "https://eikeitsu.github.io/QSC-Battery/changelog.md",
};
const text = `${JSON.stringify(manifest, null, 2)}\n`;
writeFileSync(join(docsPublic, "app-update.json"), text, "utf8");
writeFileSync(join(repoRoot, "app-update.json"), text, "utf8");
log(`wrote app-update.json version=${version} code=${versionCode}`);
log("done");
