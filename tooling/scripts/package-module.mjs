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
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { verifyUnixZip, writeUnixZip } from "./lib/write-unix-zip.mjs";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const moduleRoot = join(repoRoot, "module");
const staging = join(repoRoot, ".build", "staging");
const releaseDir = join(repoRoot, "release");
const builtWebDir = join(repoRoot, ".build", "webroot");
const webSrcDir = join(repoRoot, "webui");

const ROOT_FILES = [
  "module.prop",
  "service.sh",
  "customize.sh",
  "action.sh",
  "uninstall.sh",
  "hotinstall.sh",
  "icon.png",
];
/** 正式包：核心 + 只读诊断（不含 testing/diag2） */
const BIN_RELEASE = [
  "common.sh",
  "qsc_switch.sh",
  "list_switch.sh",
  "list_curr.sh",
  "detect_device.sh",
  "diagnose.sh",
  "test_switch.sh",
  "qscd_fetch.sh",
];
const BIN_DEBUG_EXTRA = ["testing.sh", "diag2.sh"];

const includeDebug = process.argv.includes("--debug");

/**
 * 发布变体：决定包里带哪套守护二进制。
 *  full = 两套都带（安装时按 native_impl 逐个自检）
 *  rust / c = 只带一套
 *  sh = 一套都不带，用户可在 WebUI 里现下（主包，文件名无后缀）
 * 四种包的脚本内容完全相同，差别只在 bin/qscd*-* 这几个文件。
 */
const NATIVE_VARIANTS = {
  full: ["qscd-arm64", "qscd-arm", "qscdc-arm64", "qscdc-arm"],
  rust: ["qscd-arm64", "qscd-arm"],
  c: ["qscdc-arm64", "qscdc-arm"],
  sh: [],
};

function readVariant() {
  const arg = process.argv.find((a) => a.startsWith("--native="));
  const name = arg ? arg.slice("--native=".length) : "full";
  if (!(name in NATIVE_VARIANTS)) {
    throw new Error(
      `unknown --native=${name} (expected: ${Object.keys(NATIVE_VARIANTS).join(" | ")})`,
    );
  }
  return name;
}

const variant = readVariant();

function log(message) {
  console.log(`[package-module] ${message}`);
}

function readVersion() {
  const prop = readFileSync(join(moduleRoot, "module.prop"), "utf8");
  return prop.match(/^version=(.+)$/m)?.[1]?.trim() || "unknown";
}

function copyFromModule(relPath, { required = true } = {}) {
  const source = join(moduleRoot, relPath);
  const target = join(staging, relPath);
  if (!existsSync(source)) {
    if (required) throw new Error(`missing required module file: ${relPath}`);
    log(`skip missing: ${relPath}`);
    return;
  }
  mkdirSync(dirname(target), { recursive: true });
  cpSync(source, target, { recursive: true });
}

function copyDirFromModule(relPath) {
  const source = join(moduleRoot, relPath);
  if (!existsSync(source)) throw new Error(`missing required directory: ${relPath}`);
  mkdirSync(join(staging, relPath), { recursive: true });
  for (const entry of readdirSync(source, { withFileTypes: true })) {
    const child = join(relPath, entry.name);
    if (entry.isDirectory()) copyDirFromModule(child);
    else copyFromModule(child);
  }
}

function listLibScripts() {
  const dir = join(moduleRoot, "bin", "lib");
  if (!existsSync(dir)) throw new Error("missing bin/lib");
  const files = readdirSync(dir)
    .filter((name) => name.endsWith(".sh"))
    .sort();
  if (!files.length) throw new Error("bin/lib has no .sh files");
  return files;
}

function maxMtime(path) {
  const st = statSync(path);
  if (st.isFile()) return st.mtimeMs;
  let max = st.mtimeMs;
  for (const name of readdirSync(path)) {
    if (name === "node_modules" || name === "dist") continue;
    max = Math.max(max, maxMtime(join(path, name)));
  }
  return max;
}

function ensureBuiltWeb() {
  const marker = join(builtWebDir, "index.html");
  const stale =
    !existsSync(marker) ||
    (existsSync(webSrcDir) && maxMtime(webSrcDir) > statSync(marker).mtimeMs);
  if (!stale) {
    log("webroot up to date");
    return;
  }
  log("webroot missing or stale — running build:web");
  execSync("npm run build:web", { cwd: repoRoot, stdio: "inherit" });
  if (!existsSync(marker)) {
    throw new Error("build:web did not produce .build/webroot/index.html");
  }
}

/**
 * 原生事件等待器：Rust 版与 C 版两套都进包，装机时按 native_impl 逐个自检。
 * 任一套缺失都不阻断打包——少一套就少一个候选，全缺则退回定时轮询。
 */
const NATIVE_IMPLS = [
  { name: "rust", script: "build-native.mjs", bins: ["qscd-arm64", "qscd-arm"] },
  { name: "c", script: "build-native-c.mjs", bins: ["qscdc-arm64", "qscdc-arm"] },
];
function ensureNative() {
  const wanted = new Set(NATIVE_VARIANTS[variant]);
  if (!wanted.size) {
    log("native: sh 变体，跳过二进制构建");
    return;
  }
  for (const impl of NATIVE_IMPLS) {
    if (!impl.bins.some((name) => wanted.has(name))) continue;
    const script = join(repoRoot, "tooling", "scripts", impl.script);
    if (!existsSync(script)) continue;
    if (impl.bins.every((name) => existsSync(join(moduleRoot, "bin", name)))) {
      log(`native qscd (${impl.name}) up to date`);
      continue;
    }
    log(`building native qscd (${impl.name})`);
    execSync(`node ${JSON.stringify(script)}`, { cwd: repoRoot, stdio: "inherit" });
  }
}

function stripJsonComments(text) {
  return String(text || "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "")
    .replace(/,\s*([\]}])/g, "$1");
}

function normalizeCurrentJsonInStaging() {
  const target = join(staging, "config", "current.json");
  if (!existsSync(target)) return;
  const raw = readFileSync(target, "utf8");
  const parsed = JSON.parse(stripJsonComments(raw));
  writeFileSync(target, `${JSON.stringify(parsed, null, 2)}\n`, "utf8");
  log("stripped comments from config/current.json for package");
}

function validateShellFile(relPath) {
  const content = readFileSync(join(moduleRoot, relPath), "utf8");
  if (content.includes("\r\n")) {
    throw new Error(`CRLF is not allowed in shell script: ${relPath}`);
  }
  if (!content.startsWith("#!/system/bin/sh")) {
    throw new Error(`invalid shell shebang: ${relPath}`);
  }
}

function validateSources(libFiles) {
  const scripts = [
    ...ROOT_FILES.filter((file) => file.endsWith(".sh")),
    ...BIN_RELEASE.map((file) => join("bin", file)),
    ...libFiles.map((file) => join("bin", "lib", file)),
  ];
  if (includeDebug) {
    scripts.push(...BIN_DEBUG_EXTRA.map((file) => join("bin", file)));
  }
  for (const rel of scripts) validateShellFile(rel);

  const updateBinary = join("META-INF", "com", "google", "android", "update-binary");
  if (!existsSync(join(moduleRoot, updateBinary))) {
    throw new Error(`missing ${updateBinary}`);
  }
}

function copyBuiltWebroot() {
  if (!existsSync(join(builtWebDir, "index.html"))) {
    throw new Error("missing .build/webroot/index.html");
  }
  cpSync(builtWebDir, join(staging, "webroot"), { recursive: true });
}

const version = readVersion();
// sh 是主包，不带变体后缀；其余变体加 -full / -rust / -c
const variantSuffix = variant === "sh" ? "" : `-${variant}`;
const zipName = includeDebug
  ? `QSC-Battery_v${version}${variantSuffix}-debug.zip`
  : `QSC-Battery_v${version}${variantSuffix}.zip`;
const zipPath = join(releaseDir, zipName);
const libFiles = listLibScripts();

ensureBuiltWeb();
ensureNative();
validateSources(libFiles);

rmSync(staging, { recursive: true, force: true });
mkdirSync(staging, { recursive: true });
mkdirSync(releaseDir, { recursive: true });
mkdirSync(join(staging, "data"), { recursive: true });
writeFileSync(join(staging, "data", ".keep"), "");
mkdirSync(join(staging, "bin"), { recursive: true });

for (const file of ROOT_FILES) copyFromModule(file);
copyDirFromModule("META-INF");
copyDirFromModule("config");
normalizeCurrentJsonInStaging();
for (const file of BIN_RELEASE) copyFromModule(join("bin", file));
for (const file of libFiles) copyFromModule(join("bin", "lib", file));
log(`bin/lib: ${libFiles.join(", ")}`);
{
  const wanted = NATIVE_VARIANTS[variant];
  const shipped = wanted.filter((name) => existsSync(join(moduleRoot, "bin", name)));
  for (const name of shipped) copyFromModule(join("bin", name));
  const missing = wanted.filter((name) => !shipped.includes(name));
  if (missing.length) {
    // CI 必须四个都在；本地缺编译器时允许少带，安装后可在 WebUI 里下载
    const message = `native: 变体 ${variant} 缺少 ${missing.join(", ")}`;
    if (process.env.CI === "true" || process.env.REQUIRE_NATIVE === "1") {
      throw new Error(message);
    }
    log(message);
  }
  log(
    shipped.length
      ? `native (${variant}): ${shipped.join(", ")}`
      : `native (${variant}): none — 由 WebUI 按需下载`,
  );
}
if (includeDebug) {
  for (const file of BIN_DEBUG_EXTRA) copyFromModule(join("bin", file));
  writeFileSync(
    join(staging, "bin", ".qsc_debug"),
    "debug tools: testing.sh diag2.sh\n",
    "utf8",
  );
  log("debug package: included testing.sh, diag2.sh");
} else {
  log("release package: diagnose only (no testing/diag2)");
}
copyBuiltWebroot();

if (existsSync(zipPath)) rmSync(zipPath);
log(`packaging ${zipName}...`);
writeUnixZip(staging, zipPath);
const entries = verifyUnixZip(zipPath, [
  "META-INF/com/google/android/update-binary",
  "module.prop",
  "hotinstall.sh",
  "bin/lib/hot_update.sh",
  "webroot/index.html",
]);
log(
  `created ${zipPath} (${(statSync(zipPath).size / 1024).toFixed(1)} KB, ${entries.length} files)`,
);
rmSync(staging, { recursive: true, force: true });
log("done");
