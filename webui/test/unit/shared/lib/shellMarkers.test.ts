import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// webui/test/unit/shared/lib → 仓库根目录（上溯 5 级）
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../../../..");

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
    const switchSh = readFileSync(join(repoRoot, "module/bin/qsc_switch.sh"), "utf8");
    expect(switchSh).toMatch(/qsc_event_stop/);
    expect(switchSh).toMatch(/qsc_event_plug/);
  });
});
