#!/usr/bin/env node
/**
 * 交叉编译 native/qscd-c（事件等待器的 C 实现）到 Android arm64 / armv7。
 *
 * 依赖只有 Android NDK 的 clang——不需要 Rust 工具链，因此在没有 cargo 的
 * 环境里也能产出可用的原生等待器。输出名带 c 后缀（qscdc-*），与 Rust 版
 * 并存；安装时优先用 Rust 版，自检不过再退到 C 版。
 * 本地缺依赖时打印跳过并退出 0；CI 或 REQUIRE_NATIVE=1 时视为失败。
 */
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const srcDir = join(repoRoot, "native", "qscd-c");
const srcFile = join(srcDir, "qscd.c");
const outDir = join(repoRoot, "module", "bin");

const required = process.env.CI === "true" || process.env.REQUIRE_NATIVE === "1";
/** API 24：与 Rust 版保持一致，覆盖 Android 7+ */
const API = process.env.QSCD_ANDROID_API || "24";

const TARGETS = [
  { clang: "aarch64-linux-android", out: "qscdc-arm64" },
  { clang: "armv7a-linux-androideabi", out: "qscdc-arm" },
];

/** -Os 换小体积；栈保护与 RELRO 让这个常驻等待器更难被利用 */
const CFLAGS = [
  // gnu11 而非 c11：严格 ANSI 下 glibc 会收起 POSIX 声明（recv/sleep/close）
  "-std=gnu11",
  "-Os",
  "-fstack-protector-strong",
  // NDK 自己也会定义 _FORTIFY_SOURCE，先撤掉避免与 -Werror 撞重定义
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
  console.log(`[build-native-c] ${message}`);
}

function skip(reason) {
  if (required) {
    console.error(`[build-native-c] ${reason}`);
    process.exit(1);
  }
  console.warn(`[build-native-c] ${reason} — skip locally (CI builds it)`);
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

/**
 * 取交叉编译用的 clang。
 * 优先带 API 号的 wrapper（r26 及以前的常规做法），缺失时退回
 * `clang --target=<triple><api>`——NDK r27+ 已移除这批 wrapper。
 */
function clangFor(bin, clangPrefix) {
  const exe = process.platform === "win32" ? ".cmd" : "";
  const wrapper = join(bin, `${clangPrefix}${API}-clang${exe}`);
  if (existsSync(wrapper)) return { cc: wrapper, args: [] };
  const plain = join(bin, `clang${process.platform === "win32" ? ".exe" : ""}`);
  if (existsSync(plain)) return { cc: plain, args: [`--target=${clangPrefix}${API}`] };
  return null;
}

if (!existsSync(srcFile)) skip("native/qscd-c/qscd.c not found");

const ndk = ndkRoot();
if (!ndk) skip("Android NDK not found (set ANDROID_NDK_ROOT)");
const bin = toolchainBin(ndk);
if (!bin) skip(`NDK toolchain bin not found under ${ndk}`);

mkdirSync(outDir, { recursive: true });
let built = 0;

for (const target of TARGETS) {
  const clang = clangFor(bin, target.clang);
  if (!clang) skip(`missing NDK clang for ${target.clang} (API ${API})`);

  const dest = join(outDir, target.out);
  log(`building ${target.out} (API ${API})`);
  const r = spawnSync(clang.cc, [...clang.args, ...CFLAGS, srcFile, "-o", dest], {
    cwd: srcDir,
    stdio: "inherit",
    shell: true,
  });
  if (r.status !== 0) {
    console.error(`[build-native-c] clang failed for ${target.out}`);
    process.exit(1);
  }
  if (!existsSync(dest)) {
    console.error(`[build-native-c] missing artifact: ${dest}`);
    process.exit(1);
  }
  log(`${target.out}: ${(statSync(dest).size / 1024).toFixed(1)} KB`);
  built += 1;
}

log(`done (${built} binaries)`);
