import { describe, expect, it } from "vitest";
import { sanitizeSettings } from "./limits";
import { DEFAULTS } from "./defaults";
import { BinaryFlag } from "./enums";
import type { Settings } from "@/shared/types";

function make(overrides: Partial<Settings>): Settings {
  return { ...DEFAULTS, ...overrides };
}

describe("sanitizeSettings: 曲线显示与采样的联动", () => {
  it("关闭曲线时把采样一并关掉", () => {
    const { value, fixed } = sanitizeSettings(
      make({ chart_show: BinaryFlag.Off, history_enable: BinaryFlag.On }),
    );
    expect(value.chart_show).toBe(BinaryFlag.Off);
    expect(value.history_enable).toBe(BinaryFlag.Off);
    expect(fixed).toBe(true);
  });

  it("显示曲线时不强制开采样，两者可独立", () => {
    const { value } = sanitizeSettings(
      make({ chart_show: BinaryFlag.On, history_enable: BinaryFlag.Off }),
    );
    expect(value.chart_show).toBe(BinaryFlag.On);
    expect(value.history_enable).toBe(BinaryFlag.Off);
  });

  it("两者都开时保持不变", () => {
    const { value } = sanitizeSettings(
      make({ chart_show: BinaryFlag.On, history_enable: BinaryFlag.On }),
    );
    expect(value.chart_show).toBe(BinaryFlag.On);
    expect(value.history_enable).toBe(BinaryFlag.On);
  });
});

describe("sanitizeSettings: 守护相关键", () => {
  it("native_daemon 只接受 0/1，非法值回落到开", () => {
    expect(sanitizeSettings(make({ native_daemon: "0" })).value.native_daemon).toBe("0");
    expect(sanitizeSettings(make({ native_daemon: "1" })).value.native_daemon).toBe("1");
    expect(sanitizeSettings(make({ native_daemon: "yes" })).value.native_daemon).toBe(
      "1",
    );
  });

  it("native_impl 只接受 rust / c / off", () => {
    expect(sanitizeSettings(make({ native_impl: "c" })).value.native_impl).toBe("c");
    expect(sanitizeSettings(make({ native_impl: "off" })).value.native_impl).toBe("off");
    expect(sanitizeSettings(make({ native_impl: "go" })).value.native_impl).toBe("rust");
  });
});
