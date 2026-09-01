#!/usr/bin/env node
/**
 * 交叉编译 native/qscd（事件等待器）到 Android arm64 / armv7。
 *
 * 依赖：cargo + Android NDK（NDK 的 clang 同时充当链接器）。
 * 本地缺任一依赖时打印跳过并退出 0——模块在没有该二进制时会自动退回定时轮询。
 * CI 或 REQUIRE_NATIVE=1 时缺依赖视为失败。
 */
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const crateDir = join(repoRoot, "native", "qscd");
const outDir = join(repoRoot, "module", "bin");

const required = process.env.CI === "true" || process.env.REQUIRE_NATIVE === "1";
/** API 24：覆盖 Android 7+，低于此的机型仍可用 shell 定时轮询 */
const API = process.env.QSCD_ANDROID_API || "24";

const TARGETS = [
  { triple: "aarch64-linux-android", clang: "aarch64-linux-android", out: "qscd-arm64" },
  {
    triple: "armv7-linux-androideabi",
    clang: "armv7a-linux-androideabi",
    out: "qscd-arm",
  },
];

function log(message) {
  console.log(`[build-native] ${message}`);
}

function skip(reason) {
  if (required) {
    console.error(`[build-native] ${reason}`);
    process.exit(1);
  }
  console.warn(`[build-native] ${reason} — skip locally (CI builds it)`);
  process.exit(0);
}

function hasCargo() {
  const r = spawnSync("cargo", ["--version"], { encoding: "utf8", shell: true });
  return r.status === 0;
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
  // prebuilt 下只有一个宿主目录（linux-x86_64 / darwin-x86_64 / windows-x86_64）
  for (const name of readdirSync(base)) {
    const bin = join(base, name, "bin");
    if (existsSync(bin)) return bin;
  }
  return null;
}

/**
 * 取充当链接器的 clang。
 * 优先带 API 号的 wrapper（r26 及以前的常规做法）；缺失时退回裸 clang，
 * 并把 --target 作为链接参数补上——NDK r27+ 已移除这批 wrapper。
 */
function clangFor(bin, clangPrefix) {
  const exe = process.platform === "win32" ? ".cmd" : "";
  const wrapper = join(bin, `${clangPrefix}${API}-clang${exe}`);
  if (existsSync(wrapper)) return { cc: wrapper, target: null };
  const plain = join(bin, `clang${process.platform === "win32" ? ".exe" : ""}`);
  if (existsSync(plain)) return { cc: plain, target: `${clangPrefix}${API}` };
  return null;
}

if (!existsSync(join(crateDir, "Cargo.toml"))) skip("native/qscd not found");
if (!hasCargo()) skip("cargo not found");

const ndk = ndkRoot();
if (!ndk) skip("Android NDK not found (set ANDROID_NDK_ROOT)");
const bin = toolchainBin(ndk);
if (!bin) skip(`NDK toolchain bin not found under ${ndk}`);

const cargoVer = spawnSync("cargo", ["--version"], { encoding: "utf8", shell: true });
log(
  `start: api=${API} ndk=${ndk} out=${outDir}${cargoVer.stdout ? ` cargo=${cargoVer.stdout.trim()}` : ""}`,
);

mkdirSync(outDir, { recursive: true });
let built = 0;
const startedAt = Date.now();

for (const target of TARGETS) {
  const clang = clangFor(bin, target.clang);
  if (!clang) skip(`missing NDK clang for ${target.triple} (API ${API})`);

  const envKey = `CARGO_TARGET_${target.triple.toUpperCase().replace(/-/g, "_")}_LINKER`;
  const env = {
    ...process.env,
    [envKey]: clang.cc,
    [`CC_${target.triple.replace(/-/g, "_")}`]: clang.cc,
  };
  // 裸 clang 需要显式目标；linker 环境变量只接受可执行文件，故走 link-arg
  if (clang.target) {
    const flag = `-C link-arg=--target=${clang.target}`;
    env[`CARGO_TARGET_${target.triple.toUpperCase().replace(/-/g, "_")}_RUSTFLAGS`] =
      flag;
  }

  log(
    `building ${target.triple} -> ${target.out} linker=${clang.cc}${clang.target ? ` target=${clang.target}` : ""}`,
  );
  const args = ["build", "--release", "--target", target.triple];
  // 有 Cargo.lock 就锁版本，保证 CI 与本地一致
  if (existsSync(join(crateDir, "Cargo.lock"))) args.splice(2, 0, "--locked");
  const r = spawnSync("cargo", args, {
    cwd: crateDir,
    env,
    stdio: "inherit",
    shell: true,
  });
  if (r.status !== 0) {
    console.error(`[build-native] cargo build failed for ${target.triple}`);
    process.exit(1);
  }

  const artifact = join(crateDir, "target", target.triple, "release", "qscd");
  if (!existsSync(artifact)) {
    console.error(`[build-native] missing artifact: ${artifact}`);
    process.exit(1);
  }
  const dest = join(outDir, target.out);
  copyFileSync(artifact, dest);
  log(`ok ${target.out}: ${dest} (${(statSync(dest).size / 1024).toFixed(1)} KB)`);
  built += 1;
}

log(`done (${built} binaries, ${((Date.now() - startedAt) / 1000).toFixed(1)}s)`);
