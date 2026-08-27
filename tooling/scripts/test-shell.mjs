#!/usr/bin/env node
/**
 * 停充决策层的行为测试：在临时目录里搭一套假 sysfs + 假开关节点，
 * 跑真正的 bin/qsc_switch.sh，断言它的判定结果。
 *
 * 模块脚本读电池输入时统一走 $PSDIR（= $QSC_SYSFS_ROOT/sys/class/power_supply），
 * 环境变量为空时展开结果与线上写死的绝对路径完全一致，所以被测的就是生产代码。
 * 停充候选节点列表仍是绝对路径，在测试机上不存在会被跳过，用例通过
 * data/list_switch 显式注入自己的假节点。
 *
 * 本机没有 POSIX shell（Windows）时打印跳过并退出 0；CI 或
 * REQUIRE_SHELL_TESTS=1 时视为失败。
 */
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { existsSync } from "node:fs";
import { appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { cases } from "../test/shell/cases.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const MODULE_SRC = join(ROOT, "module");
const REQUIRED = process.env.CI === "true" || process.env.REQUIRE_SHELL_TESTS === "1";
const KEEP = process.env.KEEP_SHELL_TEST_DIRS === "1";

// 传给被测脚本的路径统一用正斜杠：Linux 上本来如此，Windows 上（Git bash 等）
// 也只有这种形式能被 POSIX 层认出来
const posix = (p) => p.replace(/\\/g, "/");

function findShell() {
  // 显式指定：可用来在 CI 里对同一套用例多跑几种 shell（ash / dash / mksh）
  const explicit = process.env.QSC_TEST_SHELL;
  if (explicit) return { cmd: explicit, args: [], label: explicit };
  if (process.platform === "win32") return null;
  const which = (bin) => spawnSync("which", [bin], { encoding: "utf8" });
  // busybox ash 最接近 Magisk 环境；dash 是次选的严格 POSIX 实现
  for (const bin of ["busybox", "dash", "sh"]) {
    const r = which(bin);
    if (r.status === 0 && r.stdout.trim()) {
      const path = r.stdout.trim().split("\n")[0];
      return bin === "busybox" ? { cmd: path, args: ["sh"], label: "busybox sh" } : { cmd: path, args: [], label: bin };
    }
  }
  return null;
}

function buildConfig(overrides) {
  // 以真实模板为底，把覆盖项追加在末尾：解析是后出现的键生效，
  // 这样模板里新增的键不会在测试里悄悄缺失
  const base = readFileSync(join(MODULE_SRC, "config/config.conf"), "utf8");
  const extra = Object.entries(overrides)
    .map(([k, v]) => `${k}=${v}`)
    .join("\n");
  return `${base}\n# ---- test overrides ----\n${extra}\n`;
}

function setupCase(tc) {
  const dir = mkdtempSync(join(tmpdir(), "qsc-shell-test-"));
  const mod = join(dir, "module");
  mkdirSync(mod, { recursive: true });
  cpSync(join(MODULE_SRC, "bin"), join(mod, "bin"), { recursive: true });
  cpSync(join(MODULE_SRC, "module.prop"), join(mod, "module.prop"));
  mkdirSync(join(mod, "config"), { recursive: true });
  writeFileSync(join(mod, "config/config.conf"), buildConfig(tc.config ?? {}));
  const data = join(mod, "data");
  mkdirSync(data, { recursive: true });

  const ps = join(dir, "sys/class/power_supply");
  for (const [rel, val] of Object.entries(tc.sysfs ?? {})) {
    const p = join(ps, rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, `${val}\n`);
  }

  const nodePath = join(dir, "fake_switch_node");
  writeFileSync(nodePath, `${tc.node.initial}\n`);
  const entry = `${posix(nodePath)},start=${tc.node.start},stop=${tc.node.stop}`;
  writeFileSync(join(data, "list_switch"), `${entry}\n`);
  if (tc.activeSwitch) writeFileSync(join(data, "active_switch"), `${entry}\n`);

  for (const [name, content] of Object.entries(tc.data ?? {})) {
    writeFileSync(join(data, name), content);
  }
  return { dir, mod, nodePath };
}

function readTrimmed(p) {
  try {
    return readFileSync(p, "utf8").trim();
  } catch {
    return "";
  }
}

function describeFailure(tc, env, ctx) {
  const lines = [];
  const node = readTrimmed(ctx.nodePath);
  lines.push(`    节点值: ${JSON.stringify(node)}（期望 ${JSON.stringify(tc.expect.node)}）`);
  for (const name of Object.keys(tc.expect.files ?? {})) {
    lines.push(`    data/${name} 存在: ${existsSync(join(ctx.mod, "data", name))}`);
  }
  const desc = readTrimmed(join(ctx.mod, "module.prop"))
    .split("\n")
    .find((l) => l.startsWith("description="));
  lines.push(`    简介: ${desc ?? "(无)"}`);
  const log = readTrimmed(join(ctx.mod, "data/log.log"));
  if (log) lines.push(`    日志:\n${log.replace(/^/gm, "      ")}`);
  if (env.stderr?.trim()) lines.push(`    stderr:\n${env.stderr.trim().replace(/^/gm, "      ")}`);
  return lines.join("\n");
}

function checkCase(tc, ctx) {
  const errors = [];
  const node = readTrimmed(ctx.nodePath);
  if (node !== tc.expect.node) {
    errors.push(`节点值应为 ${JSON.stringify(tc.expect.node)}，实际 ${JSON.stringify(node)}`);
  }
  for (const [name, want] of Object.entries(tc.expect.files ?? {})) {
    const got = existsSync(join(ctx.mod, "data", name));
    if (got !== want) errors.push(`data/${name} 存在性应为 ${want}，实际 ${got}`);
  }
  if (tc.expect.descIncludes) {
    const prop = readTrimmed(join(ctx.mod, "module.prop"));
    const desc = prop.split("\n").find((l) => l.startsWith("description=")) ?? "";
    if (!desc.includes(tc.expect.descIncludes)) {
      errors.push(`简介应含「${tc.expect.descIncludes}」，实际 ${desc}`);
    }
  }
  if (tc.expect.logIncludes) {
    const log = readTrimmed(join(ctx.mod, "data/log.log"));
    if (!log.includes(tc.expect.logIncludes)) {
      errors.push(`日志应含「${tc.expect.logIncludes}」`);
    }
  }
  return errors;
}

function main() {
  const shell = findShell();
  if (!shell) {
    const msg = "[test:shell] 未找到可用的 POSIX shell，已跳过（Windows 本机正常）";
    if (REQUIRED) {
      console.error(msg.replace("已跳过", "必须可用"));
      process.exit(1);
    }
    console.warn(msg);
    return;
  }
  console.log(`[test:shell] 使用 ${shell.label}`);

  let failed = 0;
  const summary = [];
  for (const tc of cases) {
    const ctx = setupCase(tc);
    const run = spawnSync(shell.cmd, [...shell.args, posix(join(ctx.mod, "bin/qsc_switch.sh"))], {
      encoding: "utf8",
      timeout: 120_000,
      env: {
        ...process.env,
        MODDIR: posix(ctx.mod),
        QSC_SYSFS_ROOT: posix(ctx.dir),
        // 判定层不该依赖 PATH 之外的东西；保持继承以便用到 sed/awk/find
      },
    });
    const errors = run.error ? [`执行失败: ${run.error.message}`] : checkCase(tc, ctx);
    if (errors.length === 0) {
      console.log(`  ✓ ${tc.name}`);
      summary.push(`| ✅ | ${tc.name} | |`);
    } else {
      failed++;
      console.error(`  ✗ ${tc.name}`);
      for (const e of errors) console.error(`    - ${e}`);
      console.error(describeFailure(tc, run, ctx));
      summary.push(`| ❌ | ${tc.name} | ${errors.join("；")} |`);
    }
    if (!KEEP) rmSync(ctx.dir, { recursive: true, force: true });
    else console.log(`    保留现场: ${ctx.dir}`);
  }

  if (process.env.GITHUB_STEP_SUMMARY) {
    const head = ["## 停充决策用例", "", "| | 用例 | 失败原因 |", "| - | - | - |"];
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, [...head, ...summary, ""].join("\n"));
  }

  console.log(`[test:shell] ${cases.length - failed}/${cases.length} 通过`);
  if (failed > 0) process.exit(1);
}

main();
