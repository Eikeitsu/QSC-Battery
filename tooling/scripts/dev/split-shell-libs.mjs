#!/usr/bin/env node
/**
 * One-shot Phase 2 splitter: extract domain fragments from oversized shell libs.
 * Safe to re-run only on unsplit originals (checks for existing wrappers).
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "../..");
const lib = join(root, "module/bin/lib");
const mod = join(root, "module");

function linesOf(path) {
  return readFileSync(path, "utf8").replace(/\r\n/g, "\n").split("\n");
}

function write(path, content) {
  writeFileSync(path, content.endsWith("\n") ? content : `${content}\n`, "utf8");
  const n = content.split("\n").length;
  console.log(`wrote ${path.slice(root.length + 1)} (~${n} lines)`);
}

function sliceJoin(lines, start1, end1) {
  return lines.slice(start1 - 1, end1).join("\n").replace(/\n+$/, "") + "\n";
}

function alreadySplit(path, marker) {
  const t = readFileSync(path, "utf8");
  return t.includes(marker);
}

// --- charge.sh ---
{
  const p = join(lib, "charge.sh");
  if (alreadySplit(p, "charge_nodes.sh")) {
    console.log("skip charge.sh (already split)");
  } else {
    const L = linesOf(p);
    write(join(lib, "charge_nodes.sh"), `#!/system/bin/sh\n# charge: switch node lists\n${sliceJoin(L, 3, 90)}`);
    write(join(lib, "charge_write.sh"), `#!/system/bin/sh\n# charge: write / switch list helpers\n${sliceJoin(L, 92, 453)}`);
    write(join(lib, "charge_mca.sh"), `#!/system/bin/sh\n# charge: MCA / preferred / power stop-start-reset\n${sliceJoin(L, 455, 705)}`);
    write(join(lib, "charge_unplug.sh"), `#!/system/bin/sh\n# charge: unplug detect / orphan stop\n${sliceJoin(L, 707, 825)}`);
    write(join(lib, "charge_restore.sh"), `#!/system/bin/sh\n# charge: restore switches / MCA charge\n${sliceJoin(L, 827, L.length)}`);
    write(
      p,
      `#!/system/bin/sh
# 充电节点写入：用户 power_switch + 通用 fallback + MCA / preferred 优先
# 实现拆到 charge_*.sh；本文件保持为 common.sh 的稳定入口。
. "$LIBDIR/charge_nodes.sh"
. "$LIBDIR/charge_write.sh"
. "$LIBDIR/charge_mca.sh"
. "$LIBDIR/charge_unplug.sh"
. "$LIBDIR/charge_restore.sh"
`,
    );
  }
}

// --- current.sh ---
{
  const p = join(lib, "current.sh");
  if (alreadySplit(p, "current_limits.sh")) {
    console.log("skip current.sh (already split)");
  } else {
    const L = linesOf(p);
    // Drop duplicate shebang from fragment bodies when present
    const limits = sliceJoin(L, 1, 398).replace(/^#!\/system\/bin\/sh\n/, "");
    write(join(lib, "current_limits.sh"), `#!/system/bin/sh\n# current: probe / limits / node build\n${limits}`);
    write(join(lib, "current_bypass.sh"), `#!/system/bin/sh\n# current: hardware bypass\n${sliceJoin(L, 399, 460)}`);
    write(join(lib, "current_apply.sh"), `#!/system/bin/sh\n# current: decide / write / apply\n${sliceJoin(L, 461, L.length)}`);
    write(
      p,
      `#!/system/bin/sh
# 电流控制（可选）：限流 / 旁路 / 写入
# 实现拆到 current_*.sh；安装时可整体删除本入口。
. "$LIBDIR/current_limits.sh"
. "$LIBDIR/current_bypass.sh"
. "$LIBDIR/current_apply.sh"
`,
    );
  }
}

// --- power_saver.sh ---
{
  const p = join(lib, "power_saver.sh");
  if (alreadySplit(p, "power_saver_plugged.sh")) {
    console.log("skip power_saver.sh (already split)");
  } else {
    const L = linesOf(p);
    // 1-177 prelude+conf; 178-360 plugged; 361-514 decide/refresh; 515-end idle/native wait
    const head = sliceJoin(L, 1, 177).replace(/^#!\/system\/bin\/sh\n/, "");
    write(join(lib, "power_saver_core.sh"), `#!/system/bin/sh\n# power_saver: conf / logging helpers\n${head}`);
    write(join(lib, "power_saver_plugged.sh"), `#!/system/bin/sh\n# power_saver: plugged detection\n${sliceJoin(L, 178, 360)}`);
    write(join(lib, "power_saver_decide.sh"), `#!/system/bin/sh\n# power_saver: skip / description\n${sliceJoin(L, 361, 514)}`);
    write(join(lib, "power_saver_idle.sh"), `#!/system/bin/sh\n# power_saver: idle / native wait\n${sliceJoin(L, 515, L.length)}`);
    write(
      p,
      `#!/system/bin/sh
# 省电主循环辅助：插电判定 / 跳过轮询 / 事件等待
# 实现拆到 power_saver_*.sh；本文件保持稳定入口。
. "$LIBDIR/power_saver_core.sh"
. "$LIBDIR/power_saver_plugged.sh"
. "$LIBDIR/power_saver_decide.sh"
. "$LIBDIR/power_saver_idle.sh"
`,
    );
  }
}

// --- hot_update.sh ---
{
  const p = join(lib, "hot_update.sh");
  if (alreadySplit(p, "hot_update_txn.sh")) {
    console.log("skip hot_update.sh (already split)");
  } else {
    const L = linesOf(p);
    // Split roughly mid + finalize (verify) near end; find qsc_hot_finalize at ~722
    let finalizeAt = L.findIndex((l) => l.startsWith("qsc_hot_finalize"));
    if (finalizeAt < 0) finalizeAt = Math.floor(L.length * 0.7);
    const mid = Math.max(2, finalizeAt); // 0-based
    const head = sliceJoin(L, 1, mid).replace(/^#!\/system\/bin\/sh\n/, "");
    write(join(lib, "hot_update_txn.sh"), `#!/system/bin/sh\n# hot_update: transaction / apply\n${head}`);
    write(join(lib, "hot_update_verify.sh"), `#!/system/bin/sh\n# hot_update: finalize / verify\n${sliceJoin(L, mid + 1, L.length)}`);
    write(
      p,
      `#!/system/bin/sh
# 热更新事务：apply / finalize
# 实现拆到 hot_update_*.sh；本文件保持稳定入口。
. "$LIBDIR/hot_update_txn.sh"
. "$LIBDIR/hot_update_verify.sh"
`,
    );
  }
}

console.log("phase2 shell lib splits done");
