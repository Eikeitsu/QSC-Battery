#!/usr/bin/env node
import { execSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const moduleRoot = join(repoRoot, "module");
const staging = join(repoRoot, ".build", "staging");
const releaseDir = join(repoRoot, "release");
const builtWebDir = join(repoRoot, ".build", "webroot");

const ROOT_FILES = [
  "module.prop",
  "service.sh",
  "customize.sh",
  "action.sh",
  "uninstall.sh",
];
const BIN_FILES = ["common.sh", "qsc_switch.sh", "list_switch.sh"];
const BIN_DEBUG_FILES = ["testing.sh", "diagnose.sh", "diag2.sh"];

const includeDebug = process.argv.includes("--debug");

function log(message) {
  console.log(`[package-module] ${message}`);
}

function readVersion() {
  const prop = readFileSync(join(moduleRoot, "module.prop"), "utf8");
  return prop.match(/^version=(.+)$/m)?.[1]?.trim() || "unknown";
}

function copyFromModule(relPath) {
  const source = join(moduleRoot, relPath);
  const target = join(staging, relPath);
  if (!existsSync(source)) {
    log(`skip missing: ${relPath}`);
    return;
  }
  mkdirSync(dirname(target), { recursive: true });
  cpSync(source, target, { recursive: true });
}

function copyDirFromModule(relPath, { filter } = {}) {
  const source = join(moduleRoot, relPath);
  if (!existsSync(source)) return;
  mkdirSync(join(staging, relPath), { recursive: true });
  for (const entry of readdirSync(source, { withFileTypes: true })) {
    const child = join(relPath, entry.name);
    if (filter && !filter(child, entry)) continue;
    if (entry.isDirectory()) copyDirFromModule(child, { filter });
    else copyFromModule(child);
  }
}

function copyBuiltWebroot() {
  if (!existsSync(builtWebDir)) {
    throw new Error("missing .build/webroot — run npm run build:web first");
  }
  cpSync(builtWebDir, join(staging, "webroot"), { recursive: true });
}

function createZip(zipPath) {
  if (process.platform === "win32") {
    const escapedZip = zipPath.replace(/'/g, "''");
    const escapedStaging = staging.replace(/'/g, "''");
    const ps = [
      `$staging = '${escapedStaging}'`,
      `$zip = '${escapedZip}'`,
      "if (Test-Path $zip) { Remove-Item $zip -Force }",
      "Push-Location $staging",
      "Compress-Archive -Path * -DestinationPath $zip -Force",
      "Pop-Location",
    ].join("; ");
    execSync(`powershell -NoProfile -Command "${ps}"`, { stdio: "inherit" });
    return;
  }
  execSync(`cd "${staging}" && zip -qr9 "${zipPath}" .`, { stdio: "inherit" });
}

const version = readVersion();
const zipName = `QSC-Battery_v${version}.zip`;
const zipPath = join(releaseDir, zipName);

rmSync(staging, { recursive: true, force: true });
mkdirSync(staging, { recursive: true });
mkdirSync(releaseDir, { recursive: true });
mkdirSync(join(staging, "data"), { recursive: true });

for (const file of ROOT_FILES) copyFromModule(file);
copyDirFromModule("META-INF");
copyDirFromModule("config");
for (const file of BIN_FILES) copyFromModule(join("bin", file));
if (includeDebug) {
  for (const file of BIN_DEBUG_FILES) copyFromModule(join("bin", file));
  log("included debug scripts");
}
copyBuiltWebroot();

if (existsSync(zipPath)) rmSync(zipPath);
log(`packaging ${zipName}...`);
createZip(zipPath);
log(`created ${zipPath} (${(statSync(zipPath).size / 1024).toFixed(1)} KB)`);
rmSync(staging, { recursive: true, force: true });
log("done");
