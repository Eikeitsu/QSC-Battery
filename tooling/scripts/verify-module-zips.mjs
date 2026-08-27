#!/usr/bin/env node
/**
 * 校验 release/ 下的模块包：每个变体都得有脚本与下载入口，
 * 原生二进制则按包名后缀断言「该有的有、该没的没」。
 *
 * 打包与发版两条工作流共用；本地 `npm run build:module:all` 之后也能直接跑，
 * 不必等 CI。设置了 GITHUB_STEP_SUMMARY 时额外写一份摘要。
 */
import { appendFileSync, existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { verifyUnixZip } from "./lib/write-unix-zip.mjs";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const releaseDir = join(repoRoot, "release");
const moduleRoot = join(repoRoot, "module");

/** 只校验本次构建的包：release/ 下常年堆着历史发布，那些不该参与断言 */
function readVersion() {
  const prop = readFileSync(join(moduleRoot, "module.prop"), "utf8");
  return prop.match(/^version=(.+)$/m)?.[1]?.trim() || "unknown";
}

/**
 * 与 build-native*.mjs 同一约定：CI 或 REQUIRE_NATIVE=1 时缺二进制即失败；
 * 本地无 NDK 时只提示，不然本地根本没法跑这个校验。
 */
const nativeRequired = process.env.CI === "true" || process.env.REQUIRE_NATIVE === "1";

/** 每个变体都必须带的脚本：热更新与守护下载入口 */
const REQUIRED_ENTRIES = ["hotinstall.sh", "bin/lib/hot_update.sh", "bin/qscd_fetch.sh"];

/** 变体 → 必须存在的原生二进制；未列出的一律不允许出现 */
const VARIANT_BINARIES = {
  full: ["bin/qscd-arm64", "bin/qscd-arm", "bin/qscdc-arm64", "bin/qscdc-arm"],
  rust: ["bin/qscd-arm64", "bin/qscd-arm"],
  c: ["bin/qscdc-arm64", "bin/qscdc-arm"],
  sh: [],
};

const ALL_BINARIES = VARIANT_BINARIES.full;

/** 由包名后缀判定变体；主包（sh）无后缀，故放在最后兜底 */
function variantOf(name) {
  const base = name.replace(/-debug\.zip$/, ".zip");
  if (base.endsWith("-full.zip")) return "full";
  if (base.endsWith("-rust.zip")) return "rust";
  if (base.endsWith("-c.zip")) return "c";
  if (/^QSC-Battery_v[^-]+\.zip$/.test(base)) return "sh";
  return null;
}

function fail(message) {
  console.error(`[verify-zips] ${message}`);
  process.exitCode = 1;
}

const version = readVersion();
const prefix = `QSC-Battery_v${version}`;

let zips = [];
try {
  zips = readdirSync(releaseDir)
    .filter((n) => n.endsWith(".zip") && n.startsWith(prefix))
    .sort();
} catch {
  console.error(`[verify-zips] release dir not found: ${releaseDir}`);
  process.exit(1);
}
if (!zips.length) {
  console.error(`[verify-zips] no zip matching ${prefix}*.zip under release/`);
  process.exit(1);
}
console.log(`[verify-zips] version ${version} (${zips.length} zips)`);

const summary = [];

for (const zip of zips) {
  const zipPath = join(releaseDir, zip);
  const variant = variantOf(zip);
  if (!variant) {
    fail(`unexpected zip name: ${zip}`);
    continue;
  }

  let names;
  try {
    // 顺带校验 CRC 与本地头，坏包不会一路混到发布
    names = verifyUnixZip(zipPath, REQUIRED_ENTRIES);
  } catch (err) {
    fail(`${zip}: ${err.message}`);
    continue;
  }

  const want = new Set(VARIANT_BINARIES[variant]);
  for (const bin of ALL_BINARIES) {
    const present = names.includes(bin);
    // 多出来的二进制一律算错：变体之间只应差在带哪套守护
    if (!want.has(bin) && present) {
      fail(`${zip}: unexpected ${bin} (variant ${variant})`);
      continue;
    }
    if (!want.has(bin) || present) continue;
    // 本机压根没编出来的，本地跑就只提示；CI 里必须失败
    const built = existsSync(join(moduleRoot, bin));
    if (nativeRequired || built) {
      fail(`${zip}: missing ${bin}`);
    } else {
      console.warn(`[verify-zips] ${zip}: missing ${bin} — 本地未编译原生守护，已跳过`);
    }
  }

  const sizeKb = (statSync(zipPath).size / 1024).toFixed(1);
  console.log(
    `[verify-zips] ${zip}: variant=${variant} files=${names.length} ${sizeKb} KB`,
  );
  summary.push(
    `- \`${zip}\` — variant \`${variant}\`, ${names.length} files, ${sizeKb} KB`,
  );
}

if (process.env.GITHUB_STEP_SUMMARY) {
  const lines = ["## Module packages", "", ...summary, ""];
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
}

if (process.exitCode) {
  console.error("[verify-zips] FAILED");
} else {
  console.log(`[verify-zips] ok (${zips.length} zips)`);
}
