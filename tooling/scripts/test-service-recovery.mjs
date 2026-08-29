#!/usr/bin/env node
/**
 * 服务等待器生命周期测试：用 fake qscd 模拟一次 netlink 失败和随后恢复，
 * 直接 source 生产版 power_saver.sh，验证失败原因、退避状态和恢复清理。
 *
 * 本机没有 POSIX shell（Windows）时跳过；CI 或 REQUIRE_SERVICE_TESTS=1 时失败。
 */
import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
  chmodSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const required = process.env.CI === "true" || process.env.REQUIRE_SERVICE_TESTS === "1";

function findShell() {
  if (process.env.QSC_TEST_SHELL)
    return {
      cmd: process.env.QSC_TEST_SHELL,
      args: [],
      label: process.env.QSC_TEST_SHELL,
    };
  if (process.platform === "win32") return null;
  for (const bin of ["busybox", "dash", "sh"]) {
    const found = spawnSync("which", [bin], { encoding: "utf8" });
    if (found.status !== 0 || !found.stdout.trim()) continue;
    const path = found.stdout.trim().split(/\r?\n/)[0];
    return bin === "busybox"
      ? { cmd: path, args: ["sh"], label: "busybox sh" }
      : { cmd: path, args: [], label: bin };
  }
  return null;
}

function posix(path) {
  return path.replace(/\\/g, "/");
}

function run(shell, moduleDir, body, sysfsRoot) {
  return spawnSync(shell.cmd, [...shell.args, "-c", body], {
    encoding: "utf8",
    timeout: 30_000,
    env: {
      ...process.env,
      MODDIR: posix(moduleDir),
      QSC_SYSFS_ROOT: posix(sysfsRoot || moduleDir),
    },
  });
}

const shell = findShell();
if (!shell) {
  const message = "[test:service-recovery] 未找到 POSIX shell，已跳过";
  if (required) {
    console.error(message.replace("已跳过", "必须可用"));
    process.exit(1);
  }
  console.warn(message);
} else {
  const dir = mkdtempSync(join(tmpdir(), "qsc-service-recovery-"));
  const moduleDir = join(dir, "module");
  const dataDir = join(moduleDir, "data");
  const fakeRoot = join(dir, "fake-sysfs");
  mkdirSync(dataDir, { recursive: true });
  mkdirSync(join(moduleDir, "config"), { recursive: true });
  cpSync(join(root, "module/bin"), join(moduleDir, "bin"), { recursive: true });
  cpSync(join(root, "module/module.prop"), join(moduleDir, "module.prop"));
  cpSync(join(root, "module/config/config.conf"), join(moduleDir, "config/config.conf"));
  writeFileSync(join(dataDir, "list_switch"), "fake,battery\n");
  mkdirSync(join(fakeRoot, "sys/class/power_supply/battery"), { recursive: true });
  writeFileSync(join(fakeRoot, "sys/class/power_supply/battery/capacity"), "50\n");
  writeFileSync(join(fakeRoot, "sys/class/power_supply/battery/status"), "Discharging\n");
  writeFileSync(join(fakeRoot, "sys/class/power_supply/battery/temp"), "300\n");

  const fakeDaemon = join(moduleDir, "bin/qscd");
  writeFileSync(
    fakeDaemon,
    [
      "#!/bin/sh",
      'case "$1" in',
      "features) echo watch ;;",
      "watch|wait-event)",
      '  if [ -f "$DATADIR/recover" ]; then exit 0; fi',
      '  echo "qscd: reason=netlink_open" >&2',
      "  exit 2",
      "  ;;",
      "esac",
      "exit 2",
      "",
    ].join("\n"),
  );
  chmodSync(fakeDaemon, 0o755);

  const descriptor = run(
    shell,
    moduleDir,
    [
      '. "$MODDIR/bin/common.sh"',
      "export DATADIR BINDIR",
      "QSC_PS_DESC_MIN_GAP=30",
      "QSC_PS_NOW=100",
      'qsc_ps_refresh_desc "$QSC_PS_NOW"',
      'printf "55\\n" > "$QSC_SYSFS_ROOT/sys/class/power_supply/battery/capacity"',
      "QSC_PS_NOW=140",
      'qsc_ps_refresh_desc "$QSC_PS_NOW"',
    ].join("\n"),
    fakeRoot,
  );
  const descriptorText = readFileSync(join(moduleDir, "module.prop"), "utf8");
  if (descriptor.status !== 0 || !descriptorText.includes("55%")) {
    process.stderr.write(
      [
        "[test:service-recovery] 简介未随统一电池快照刷新",
        `descriptor_status=${descriptor.status}`,
        `descriptor_signal=${descriptor.signal || "<none>"}`,
        `descriptor_error=${descriptor.error?.message || "<none>"}`,
        `descriptor_stdout=${descriptor.stdout || "<empty>"}`,
        `descriptor_stderr=${descriptor.stderr || "<empty>"}`,
        `descriptor_module_prop=${JSON.stringify(descriptorText)}`,
        "",
      ].join("\n"),
    );
    rmSync(dir, { recursive: true, force: true });
    process.exit(1);
  }

  const source = [
    '. "$MODDIR/bin/common.sh"',
    "export DATADIR BINDIR",
    "QSC_PS_NATIVE=1",
    "QSC_PS_WAIT_HELPER_OK=1",
    "QSC_PS_NOW=100",
    "qsc_ps_wait 0",
  ].join("\n");
  const failed = run(shell, moduleDir, source, fakeRoot);
  const marker = join(dataDir, "qscd_unusable");
  const markerText = existsSync(marker) ? readFileSync(marker, "utf8") : "";
  if (
    failed.status !== 0 ||
    !markerText.includes("reason=netlink_open") ||
    !markerText.includes("mode=watch") ||
    !markerText.includes("rc=2") ||
    !markerText.includes("at=100")
  ) {
    console.error("[test:service-recovery] 失败状态未正确记录");
    if (failed.stderr) console.error(failed.stderr);
    rmSync(dir, { recursive: true, force: true });
    process.exit(1);
  }

  writeFileSync(join(dataDir, "recover"), "1\n");
  const recovered = run(
    shell,
    moduleDir,
    [
      '. "$MODDIR/bin/common.sh"',
      "export DATADIR BINDIR",
      "QSC_PS_NATIVE=1",
      "QSC_PS_WAIT_HELPER_OK=0",
      "QSC_PS_WAIT_NEXT_RETRY=0",
      "QSC_PS_NOW=101",
      "qsc_ps_wait 0",
    ].join("\n"),
    fakeRoot,
  );
  const clean = !existsSync(marker);
  rmSync(dir, { recursive: true, force: true });
  if (recovered.status !== 0 || !clean) {
    console.error("[test:service-recovery] 等待器恢复后未清理失败状态");
    if (recovered.stderr) console.error(recovered.stderr);
    process.exit(1);
  }
  console.log(`[test:service-recovery] ${shell.label} fake failure/recovery passed`);
}
