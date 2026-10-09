#!/usr/bin/env node
/**
 * Rust fmt / clippy for native/qscd-rust.
 * --fix → cargo fmt；否则 cargo fmt --check + clippy -D warnings
 * 本机无 cargo 时跳过；CI / REQUIRE_RUST_LINT=1 则失败。
 */
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";

const fix = process.argv.includes("--fix");
const requireRust = process.env.CI === "true" || process.env.REQUIRE_RUST_LINT === "1";
const crateDir = join("native", "qscd-rust");

if (!existsSync(join(crateDir, "Cargo.toml"))) {
  console.log("[lint:rust] no native/qscd-rust — skip");
  process.exit(0);
}

const cargo = spawnSync("cargo", ["--version"], { encoding: "utf8" });
if (cargo.error?.code === "ENOENT" || cargo.status !== 0) {
  const msg = "[lint:rust] cargo not installed";
  if (requireRust) {
    console.error(msg);
    process.exit(1);
  }
  console.log(`${msg} — skip`);
  process.exit(0);
}

function run(args) {
  const r = spawnSync("cargo", args, {
    cwd: crateDir,
    encoding: "utf8",
    stdio: "inherit",
  });
  return r.status ?? 1;
}

if (fix) {
  process.exit(run(["fmt"]));
}

const fmt = run(["fmt", "--check"]);
if (fmt !== 0) process.exit(fmt);

process.exit(run(["clippy", "--all-targets", "--", "-D", "warnings"]));
