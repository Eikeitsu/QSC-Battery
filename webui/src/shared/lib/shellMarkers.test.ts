import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../../..");

describe("shell helpers still present", () => {
  it("keeps notify and bg test scripts", () => {
    const utilSh = readFileSync(join(repoRoot, "module/bin/lib/util.sh"), "utf8");
    expect(utilSh).toMatch(/qsc_notify_quiet_now/);
    expect(utilSh).toMatch(/qsc_notify_kind_allowed/);
    const bg = readFileSync(join(repoRoot, "module/bin/test_switch_bg.sh"), "utf8");
    expect(bg).toMatch(/switch_test_status/);
  });
});
