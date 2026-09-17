import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// apps/webui/test/unit/shared/lib → 仓库根目录（上溯 6 级）
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../../../../..");

describe("shell helpers still present", () => {
  it("keeps notify and bg test scripts", () => {
    const utilSh = readFileSync(join(repoRoot, "module/bin/lib/util.sh"), "utf8");
    expect(utilSh).toMatch(/qsc_notify_quiet_now/);
    expect(utilSh).toMatch(/qsc_notify_kind_allowed/);
    expect(utilSh).toMatch(/qsc_notify_power_status/);
    const bg = readFileSync(join(repoRoot, "module/bin/test_switch_bg.sh"), "utf8");
    expect(bg).toMatch(/switch_test_status/);
  });

  it("wires charge event writer into common entry", () => {
    const common = readFileSync(join(repoRoot, "module/bin/common.sh"), "utf8");
    expect(common).toMatch(/event_log\.sh/);
    const events = readFileSync(join(repoRoot, "module/bin/lib/event_log.sh"), "utf8");
    expect(events).toMatch(/qsc_event_stop/);
    // qsc_switch.sh 为薄入口；事件调用在 switch_*.sh 片段中
    const switchBundle = [
      "module/bin/qsc_switch.sh",
      "module/bin/lib/switch_prelude.sh",
      "module/bin/lib/switch_charge_full.sh",
      "module/bin/lib/switch_eval.sh",
      "module/bin/lib/switch_act.sh",
    ]
      .map((rel) => readFileSync(join(repoRoot, rel), "utf8"))
      .join("\n");
    expect(switchBundle).toMatch(/qsc_event_stop/);
    expect(switchBundle).toMatch(/qsc_event_plug/);
  });
});
