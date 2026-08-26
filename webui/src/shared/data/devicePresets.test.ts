import { describe, expect, it } from "vitest";
import {
  filterPresetsByModel,
  matchModel,
  parseDevicePresetCatalog,
  resolveRepoPresetsForDisplay,
} from "./devicePresets";

describe("matchModel", () => {
  it("supports wildcard / prefix / contains", () => {
    expect(matchModel(["*"], "anything")).toBe(true);
    expect(matchModel(["Redmi K90*"], "Redmi K90 Pro")).toBe(true);
    expect(matchModel(["k90"], "Redmi K90")).toBe(true);
    expect(matchModel(["Pixel"], "Redmi K90")).toBe(false);
  });
});

describe("parseDevicePresetCatalog", () => {
  it("parses catalog object", () => {
    const catalog = parseDevicePresetCatalog(
      JSON.stringify({
        version: 1,
        updated_at: "2026-08-26",
        presets: [
          {
            id: "demo",
            name: "Demo",
            matches: ["Xiaomi*"],
            profile: {
              preferred_switch: "/sys/x",
              preferred_start: "1",
              preferred_stop: "0",
            },
          },
        ],
      }),
      "repo",
    );
    expect(catalog.presets).toHaveLength(1);
    expect(catalog.presets[0].source).toBe("repo");
    expect(catalog.updated_at).toBe("2026-08-26");
  });

  it("accepts bare array", () => {
    const catalog = parseDevicePresetCatalog(
      JSON.stringify([
        {
          id: "a",
          name: "A",
          matches: ["*"],
          profile: { preferred_switch: "" },
        },
      ]),
      "local",
    );
    expect(catalog.presets).toHaveLength(1);
    expect(catalog.presets[0].source).toBe("local");
  });
});

describe("filter / resolve", () => {
  it("filters by model and falls back to builtin", () => {
    const list = parseDevicePresetCatalog(
      JSON.stringify({
        presets: [
          {
            id: "x",
            name: "X",
            matches: ["Pixel"],
            profile: { preferred_switch: "/a" },
          },
        ],
      }),
      "repo",
    ).presets;
    expect(filterPresetsByModel(list, "Xiaomi 17")).toHaveLength(0);
    expect(resolveRepoPresetsForDisplay([]).length).toBeGreaterThan(0);
    expect(resolveRepoPresetsForDisplay(list)).toEqual(list);
  });
});
