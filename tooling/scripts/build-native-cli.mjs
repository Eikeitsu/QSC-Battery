#!/usr/bin/env node
/**
 * 交叉编译 native/qsc-cli → module/bin/qsc-arm64|qsc-arm
 * 薄包装，体积很小；缺 NDK 时本地跳过（CI / REQUIRE_NATIVE=1 则失败）。
 */
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const srcDir = join(repoRoot, "native", "qsc-cli");
const srcFile = join(srcDir, "qsc.c");
const outDir = join(repoRoot, "module", "bin");

const required = process.env.CI === "true" || process.env.REQUIRE_NATIVE === "1";
const API = process.env.QSCD_ANDROID_API || "24";

const TARGETS = [
  { clang: "aarch64-linux-android", out: "qsc-arm64" },
  { clang: "armv7a-linux-androideabi", out: "qsc-arm" },
];

const CFLAGS = [
  "-std=gnu11",
  "-Os",
  "-fstack-protector-strong",
  "-U_FORTIFY_SOURCE",
  "-D_FORTIFY_SOURCE=2",
  "-Wall",
  "-Wextra",
  "-Werror",
  "-Wl,-z,relro,-z,now",
  "-Wl,--gc-sections",
  "-ffunction-sections",
  "-fdata-sections",
  "-s",
];

function log(message) {
  console.log(`[build-native-cli] ${message}`);
}

function skip(reason) {
  if (required) {
    console.error(`[build-native-cli] ${reason}`);
    process.exit(1);
  }
  console.warn(`[build-native-cli] ${reason} — skip locally (CI builds it)`);
  process.exit(0);
}

function ndkRoot() {
  for (const key of ["ANDROID_NDK_ROOT", "ANDROID_NDK_HOME", "NDK_HOME"]) {
    const value = process.env[key];
    if (value && existsSync(value)) return value;
  }
  return null;
}

function toolchainBin(ndk) {
  const base = join(ndk, "toolchains", "llvm", "prebuilt");
  if (!existsSync(base)) return null;
  for (const name of readdirSync(base)) {
    const bin = join(base, name, "bin");
    if (existsSync(bin)) return bin;
  }
  return null;
}

function clangFor(bin, clangPrefix) {
  const exe = process.platform === "win32" ? ".cmd" : "";
  const wrapper = join(bin, `${clangPrefix}${API}-clang${exe}`);
  if (existsSync(wrapper)) return { cc: wrapper, args: [] };
  const plain = join(bin, `clang${process.platform === "win32" ? ".exe" : ""}`);
  if (existsSync(plain)) return { cc: plain, args: [`--target=${clangPrefix}${API}`] };
  return null;
}

if (!existsSync(srcFile)) skip("native/qsc-cli/qsc.c not found");

const ndk = ndkRoot();
if (!ndk) skip("Android NDK not found (set ANDROID_NDK_ROOT)");
const bin = toolchainBin(ndk);
if (!bin) skip(`NDK toolchain bin not found under ${ndk}`);

log(`start: api=${API} ndk=${ndk} src=${srcFile} out=${outDir}`);
mkdirSync(outDir, { recursive: true });
let built = 0;
const startedAt = Date.now();

for (const target of TARGETS) {
  const clang = clangFor(bin, target.clang);
  if (!clang) skip(`missing NDK clang for ${target.clang} (API ${API})`);

  const dest = join(outDir, target.out);
  log(
    `building ${target.out} cc=${clang.cc}${clang.args.length ? ` args=${clang.args.join(" ")}` : ""}`,
  );
  const r = spawnSync(clang.cc, [...clang.args, ...CFLAGS, srcFile, "-o", dest], {
    cwd: srcDir,
    stdio: "inherit",
    shell: true,
  });
  if (r.status !== 0) {
    console.error(`[build-native-cli] clang failed for ${target.out}`);
    process.exit(1);
  }
  if (!existsSync(dest)) {
    console.error(`[build-native-cli] missing artifact: ${dest}`);
    process.exit(1);
  }
  log(`ok ${target.out}: ${dest} (${(statSync(dest).size / 1024).toFixed(1)} KB)`);
  built += 1;
}

log(`done (${built} binaries, ${((Date.now() - startedAt) / 1000).toFixed(1)}s)`);
