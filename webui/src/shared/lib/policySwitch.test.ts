import { describe, expect, it } from "vitest";
import { looksLikePolicySwitch } from "./policySwitch";

describe("looksLikePolicySwitch", () => {
  it("flags known policy nodes", () => {
    expect(looksLikePolicySwitch("/sys/.../night_charging start=0 stop=1")).toBe(true);
    expect(looksLikePolicySwitch("/sys/.../cool_mode start=0 stop=1")).toBe(true);
    expect(
      looksLikePolicySwitch("power_switch=[/sys/x/batt_protect start=0 stop=1]"),
    ).toBe(true);
  });

  it("allows normal charge switches", () => {
    expect(looksLikePolicySwitch("/sys/.../input_suspend start=0 stop=1")).toBe(false);
    expect(looksLikePolicySwitch("/sys/.../batt_slate_mode start=0 stop=1")).toBe(false);
  });
});
