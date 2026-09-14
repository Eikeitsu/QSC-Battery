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
  "description_worker.sh",
  "list_switch.sh",
  "list_curr.sh",
  "detect_device.sh",
  "diagnose.sh",
  "test_switch.sh",
  "qscd_fetch.sh",
  "qsc_status.sh",
  "qsc.sh",
];
const BIN_DEBUG_EXTRA = ["testing.sh", "diag2.sh"];

const includeDebug = process.argv.includes("--debug");

/**
 * 发布变体（均带后缀；Magisk 在线更新指向 -full）：
 *  full = 两套守护 + WebUI + 可选内嵌 APK（update.json 默认）
 *  rust / c = 只带一套守护 + WebUI + APK
 *  sh = 不带守护（可 WebUI 现下）+ WebUI + APK
 *  lite = 不带守护、不带 WebUI、不内嵌 APK（体积最小）
 */
const PACKAGE_VARIANTS = {
  full: {
    bins: ["qscd-arm64", "qscd-arm", "qscdc-arm64", "qscdc-arm"],
    webui: true,
    apk: true,
  },
  rust: { bins: ["qscd-arm64", "qscd-arm"], webui: true, apk: true },
  c: { bins: ["qscdc-arm64", "qscdc-arm"], webui: true, apk: true },
  sh: { bins: [], webui: true, apk: true },
  lite: { bins: [], webui: false, apk: false },
};

function readVariant() {
  const arg = process.argv.find((a) => a.startsWith("--native="));
  const name = arg ? arg.slice("--native=".length) : "full";
  if (!(name in PACKAGE_VARIANTS)) {
    throw new Error(
      `unknown --native=${name} (expected: ${Object.keys(PACKAGE_VARIANTS).join(" | ")})`,
    );
  }
  return name;
}

const variant = readVariant();
const variantOpts = PACKAGE_VARIANTS[variant];

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
  if (process.env.QSC_SKIP_BUILD_WEB === "1") {
    if (existsSync(marker)) {
      log("webroot: skip build (QSC_SKIP_BUILD_WEB=1)");
      return;
    }
    const committed = join(moduleRoot, "webroot", "index.html");
    if (existsSync(committed)) {
      log("webroot: using committed module/webroot");
      rmSync(builtWebDir, { recursive: true, force: true });
      mkdirSync(builtWebDir, { recursive: true });
      cpSync(join(moduleRoot, "webroot"), builtWebDir, { recursive: true });
      return;
    }
    throw new Error("QSC_SKIP_BUILD_WEB=1 but no webroot available");
  }
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
  // CLI 包装对所有变体都打：体积很小，装完即可 /data/adb/qsc/bin/qsc
  const cliScript = join(repoRoot, "tooling", "scripts", "build-native-cli.mjs");
  const cliBins = ["qsc-arm64", "qsc-arm"];
  if (cliBins.every((name) => existsSync(join(moduleRoot, "bin", name)))) {
    log("native qsc cli up to date");
  } else if (existsSync(cliScript) && process.env.QSC_SKIP_BUILD_NATIVE !== "1") {
    log("building native qsc cli");
    execSync(`node ${JSON.stringify(cliScript)}`, { cwd: repoRoot, stdio: "inherit" });
  } else if (process.env.QSC_SKIP_BUILD_NATIVE === "1") {
    log("native qsc cli: skip (QSC_SKIP_BUILD_NATIVE=1)");
  }

  const wanted = new Set(variantOpts.bins);
  if (!wanted.size) {
    log(`native qscd: ${variant} 变体不带守护，跳过构建`);
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
    if (process.env.QSC_SKIP_BUILD_NATIVE === "1") {
      log(`native qscd (${impl.name}): missing bins but skip build`);
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
// 所有变体均带后缀：-full（在线更新默认）/ -rust / -c / -sh / -lite
const variantSuffix = `-${variant}`;
const zipName = includeDebug
  ? `QSC-Battery_v${version}${variantSuffix}-debug.zip`
  : `QSC-Battery_v${version}${variantSuffix}.zip`;
const zipPath = join(releaseDir, zipName);
const libFiles = listLibScripts();

if (variantOpts.webui) ensureBuiltWeb();
else log("lite: skip WebUI build");
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
  const wanted = variantOpts.bins;
  const shipped = wanted.filter((name) => existsSync(join(moduleRoot, "bin", name)));
  for (const name of shipped) copyFromModule(join("bin", name));
  const missing = wanted.filter((name) => !shipped.includes(name));
  if (missing.length) {
    // CI 必须变体要求的二进制都在；本地缺编译器时允许少带
    const message = `native: 变体 ${variant} 缺少 ${missing.join(", ")}`;
    if (process.env.CI === "true" || process.env.REQUIRE_NATIVE === "1") {
      throw new Error(message);
    }
    log(message);
  }
  log(
    shipped.length
      ? `native (${variant}): ${shipped.join(", ")}`
      : `native (${variant}): none${variantOpts.webui ? " — 可由 WebUI 按需下载" : ""}`,
  );

  const cliBins = ["qsc-arm64", "qsc-arm"].filter((name) =>
    existsSync(join(moduleRoot, "bin", name)),
  );
  for (const name of cliBins) copyFromModule(join("bin", name));
  if (cliBins.length) {
    log(`cli: ${cliBins.join(", ")}`);
  } else {
    log("cli: missing qsc-arm64/arm — 安装时退回 shell 包装");
  }
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
if (variantOpts.webui) {
  copyBuiltWebroot();
} else {
  log("lite: omit webroot");
}

function embedCompanionApk() {
  if (!variantOpts.apk) {
    log("lite: omit companion apk");
    return;
  }
  const candidates = [
    join(releaseDir, "QSC-Battery.apk"),
    join(repoRoot, "app", "app", "build", "outputs", "apk", "release", "app-release.apk"),
  ];
  const apk = candidates.find((p) => existsSync(p));
  if (!apk) {
    const msg =
      "companion apk: missing (expected release/QSC-Battery.apk or app release APK)";
    if (process.env.REQUIRE_COMPANION_APK === "1") {
      throw new Error(`${msg} — build the companion app first`);
    }
    log(`${msg} — packaging module without APK`);
    return;
  }
  const destDir = join(staging, "apk");
  mkdirSync(destDir, { recursive: true });
  const dest = join(destDir, "QSC-Battery.apk");
  cpSync(apk, dest);
  log(
    `companion apk: embedded ${(statSync(apk).size / 1024).toFixed(0)} KB → apk/QSC-Battery.apk`,
  );
}
embedCompanionApk();

if (existsSync(zipPath)) rmSync(zipPath);
log(`packaging ${zipName}...`);
writeUnixZip(staging, zipPath);
const requiredZipEntries = [
  "META-INF/com/google/android/update-binary",
  "module.prop",
  "hotinstall.sh",
  "bin/lib/hot_update.sh",
];
if (variantOpts.webui) requiredZipEntries.push("webroot/index.html");
const entries = verifyUnixZip(zipPath, requiredZipEntries);
if (!variantOpts.webui && entries.includes("webroot/index.html")) {
  throw new Error(`${zipName}: lite 包不应包含 webroot`);
}
if (!variantOpts.apk && entries.some((n) => n.startsWith("apk/"))) {
  throw new Error(`${zipName}: lite 包不应内嵌 apk/`);
}
log(
  `created ${zipPath} (${(statSync(zipPath).size / 1024).toFixed(1)} KB, ${entries.length} files)`,
);
rmSync(staging, { recursive: true, force: true });
log("done");
