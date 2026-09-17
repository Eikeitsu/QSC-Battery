#!/usr/bin/env node
/**
 * Split customize.sh / service.sh / qsc_switch.sh into fragments.
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "../..");
const mod = join(root, "module");
const lib = join(mod, "bin/lib");
const installDir = join(mod, "install");

function linesOf(path) {
  return readFileSync(path, "utf8").replace(/\r\n/g, "\n").split("\n");
}
function write(path, content) {
  writeFileSync(path, content.endsWith("\n") ? content : `${content}\n`, "utf8");
  console.log(
    `wrote ${path.slice(root.length + 1)} (~${content.split("\n").length} lines)`,
  );
}
function sliceJoin(lines, start1, end1) {
  return (
    lines
      .slice(start1 - 1, end1)
      .join("\n")
      .replace(/\n+$/, "") + "\n"
  );
}
function find1(lines, pred, from = 0) {
  for (let i = from; i < lines.length; i++) {
    if (pred(lines[i], i)) return i + 1;
  }
  throw new Error(`not found from ${from}: ${pred}`);
}
function funcEnd1(lines, start1) {
  let depth = 0;
  let started = false;
  for (let i = start1 - 1; i < lines.length; i++) {
    const line = lines[i];
    const opens = (line.match(/{/g) || []).length;
    const closes = (line.match(/}/g) || []).length;
    if (opens) {
      depth += opens;
      started = true;
    }
    if (closes) depth -= closes;
    if (started && depth <= 0) return i + 1;
  }
  throw new Error(`func end not found at ${start1}`);
}

mkdirSync(installDir, { recursive: true });

// --- customize.sh ---
{
  const p = join(mod, "customize.sh");
  if (existsSync(p) && readFileSync(p, "utf8").includes("install/helpers.sh")) {
    console.log("skip customize.sh");
  } else {
    const L = linesOf(p);
    const abortAt = find1(L, (l) => l.startsWith("qsc_abort()"));
    const oldNameAt = find1(L, (l) => l.startsWith("qsc_old_module_name()"));
    // helpers end just before OLD_MODULE_IDS / old module comments block preceding qsc_old_module_name
    let helpersEnd = oldNameAt - 1;
    while (
      helpersEnd > abortAt &&
      (L[helpersEnd - 1].trim() === "" ||
        L[helpersEnd - 1].startsWith("#") ||
        L[helpersEnd - 1].startsWith("OLD_"))
    ) {
      helpersEnd--;
    }
    // Actually include OLD_* vars with migrate fragment; helpers stop before OLD_MODULE_IDS
    const oldVarsAt = find1(L, (l) => l.startsWith("OLD_MODULE_IDS="));
    const uninstallEnd = funcEnd1(
      L,
      find1(L, (l) => l.startsWith("qsc_uninstall_old_module()")),
    );
    const qscdPrefAt = find1(L, (l) => l.startsWith("qscd_conf_pref()"));
    const installQscdAt = find1(L, (l) => l.startsWith("install_qscd()"));
    const installQscdEnd = funcEnd1(L, installQscdAt);
    const companionAt = find1(L, (l) => l.startsWith("install_companion_app()"));
    const companionEnd = funcEnd1(L, companionAt);
    const cliAt = find1(L, (l) => l.startsWith("install_qsc_cli()"));
    const cliEnd = funcEnd1(L, cliAt);

    write(
      join(installDir, "helpers.sh"),
      `#!/system/bin/sh\n# install: abort / conf merge\n${sliceJoin(L, abortAt, oldVarsAt - 1)}`,
    );
    write(
      join(installDir, "migrate.sh"),
      `#!/system/bin/sh\n# install: old module ids / uninstall helpers\n${sliceJoin(L, oldVarsAt, uninstallEnd)}`,
    );
    // qscd helpers from qscd_conf_pref through install_qscd function (not the call)
    write(
      join(installDir, "qscd.sh"),
      `#!/system/bin/sh\n# install: qscd helpers + install_qscd\n${sliceJoin(L, qscdPrefAt, installQscdEnd)}`,
    );
    write(
      join(installDir, "companion.sh"),
      `#!/system/bin/sh\n# install: companion APK\n${sliceJoin(L, companionAt, companionEnd)}`,
    );
    write(
      join(installDir, "cli.sh"),
      `#!/system/bin/sh\n# install: CLI\n${sliceJoin(L, cliAt, cliEnd)}`,
    );

    // Rebuild customize: remove extracted ranges, insert sources
    const keep = [];
    const inRange = (n1, a, b) => n1 >= a && n1 <= b;
    const dropRanges = [
      [abortAt, oldVarsAt - 1],
      [oldVarsAt, uninstallEnd],
      [qscdPrefAt, installQscdEnd],
      [companionAt, companionEnd],
      [cliAt, cliEnd],
    ];
    for (let i = 0; i < L.length; i++) {
      const n1 = i + 1;
      if (dropRanges.some(([a, b]) => inRange(n1, a, b))) continue;
      keep.push(L[i]);
    }
    // Insert sources after bootstrap (after QSC_INSTALL_AUTO block / before first remaining helper use)
    // Place after keys.sh bootstrap: find "QSC_INSTALL_AUTO=0" block end — insert after line containing install_auto handling
    let insertAt = keep.findIndex((l) => l.includes("跳过音量键，使用安全默认选项"));
    if (insertAt < 0)
      insertAt = keep.findIndex((l) => l.startsWith("QSC_INSTALL_AUTO=0"));
    if (insertAt < 0) insertAt = 30;
    else {
      // after closing fi of that block
      while (insertAt < keep.length && keep[insertAt] !== "fi") insertAt++;
      insertAt += 1;
    }
    const sources = [
      "",
      "# install fragments（customize.sh 文件名冻结）",
      '. "$MODPATH/install/helpers.sh"',
      '. "$MODPATH/install/migrate.sh"',
      '. "$MODPATH/install/qscd.sh"',
      '. "$MODPATH/install/companion.sh"',
      '. "$MODPATH/install/cli.sh"',
      "",
    ];
    keep.splice(insertAt, 0, ...sources);
    write(p, keep.join("\n").replace(/\n+$/, "") + "\n");
  }
}

// --- service.sh ---
{
  const p = join(mod, "service.sh");
  if (existsSync(p) && readFileSync(p, "utf8").includes("service_boot.sh")) {
    console.log("skip service.sh");
  } else {
    const L = linesOf(p);
    const loopAt0 = L.findIndex((l) => /^while true/.test(l));
    if (loopAt0 < 0) throw new Error("service loop not found");
    write(
      join(lib, "service_boot.sh"),
      `#!/system/bin/sh\n# service: boot / workers / helpers\n${sliceJoin(L, 3, loopAt0)}`,
    );
    // loop body: lines inside while...done (exclude while/done)
    let doneAt0 = L.length - 1;
    while (doneAt0 > loopAt0 && L[doneAt0].trim() !== "done") doneAt0--;
    write(
      join(lib, "service_loop.sh"),
      `#!/system/bin/sh\n# service: one loop iteration body\n${sliceJoin(L, loopAt0 + 2, doneAt0)}`,
    );
    write(
      p,
      `#!/system/bin/sh
# Magisk late_start service 入口（文件名冻结）
MODDIR=\${0%/*}
. "$MODDIR/bin/common.sh"
. "$LIBDIR/service_boot.sh"
while true ; do
	. "$LIBDIR/service_loop.sh"
done
`,
    );
  }
}

// --- qsc_switch.sh ---
{
  const p = join(mod, "bin/qsc_switch.sh");
  if (existsSync(p) && readFileSync(p, "utf8").includes("switch_prelude.sh")) {
    console.log("skip qsc_switch.sh");
  } else {
    const L = linesOf(p);
    const fullAt = find1(L, (l) => l.startsWith("qsc_charge_full()"));
    const fullEnd = funcEnd1(L, fullAt);
    const afterFull = fullEnd + 1;
    // 在 charge_eval 的 if/fi 整块结束后切开，避免 switch_act 以半截 else/fi 开头导致 shellcheck 失败
    const chargeEvalAt = find1(
      L,
      (l, i) => i >= afterFull - 1 && /^\s*if \[ "\$charge_eval" = "1" \]/.test(l),
    );
    let depth = 0;
    let chargeEvalFi = -1;
    for (let i = chargeEvalAt - 1; i < L.length; i++) {
      const t = L[i].trim();
      if (/^(if|for|while|until)\b/.test(t)) depth++;
      else if (t === "fi" || t === "done") {
        depth--;
        if (depth === 0 && t === "fi") {
          chargeEvalFi = i + 1; // 1-based inclusive
          break;
        }
      }
    }
    if (chargeEvalFi < 0) {
      throw new Error("qsc_switch: cannot find closing fi for charge_eval");
    }
    const prelude = sliceJoin(L, 3, fullAt - 1); // skip shebang + header comment + common.sh source
    write(
      join(lib, "switch_prelude.sh"),
      `#!/system/bin/sh\n# switch: conf / snapshot / early exits\n${prelude}`,
    );
    write(
      join(lib, "switch_charge_full.sh"),
      `#!/system/bin/sh\n# switch: charge_full helper\n${sliceJoin(L, fullAt, fullEnd)}`,
    );
    write(
      join(lib, "switch_eval.sh"),
      `#!/system/bin/sh\n# switch: stop/start decision\n${sliceJoin(L, afterFull, chargeEvalFi)}`,
    );
    write(
      join(lib, "switch_apply.sh"),
      `#!/system/bin/sh\n# switch: apply resume / current / description\n${sliceJoin(L, chargeEvalFi + 1, L.length)}`,
    );
    write(
      p,
      `#!/system/bin/sh
# 停充主循环：读配置/电量 → 判定 → 调用 lib/charge 写节点
# 实现拆到 lib/switch_*.sh；本文件名冻结。
. "\${0%/*}/common.sh"
. "$LIBDIR/switch_prelude.sh"
. "$LIBDIR/switch_charge_full.sh"
. "$LIBDIR/switch_eval.sh"
. "$LIBDIR/switch_apply.sh"
`,
    );
  }
}

console.log("entries split done");
