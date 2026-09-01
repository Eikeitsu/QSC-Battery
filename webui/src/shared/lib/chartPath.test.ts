import { describe, expect, it } from "vitest";
import { buildSmoothPath, downsamplePoints } from "./chartPath";

describe("downsamplePoints", () => {
  it("returns original list when within max", () => {
    const points = [{ ts: 1 }, { ts: 2 }, { ts: 3 }];
    expect(downsamplePoints(points, 5)).toEqual(points);
  });

  it("keeps first and last when downsampling", () => {
    const points = Array.from({ length: 10 }, (_, i) => ({ ts: i }));
    const out = downsamplePoints(points, 3);
    expect(out).toHaveLength(3);
    expect(out[0]).toEqual({ ts: 0 });
    expect(out[out.length - 1]).toEqual({ ts: 9 });
  });
});

describe("buildSmoothPath", () => {
  it("returns empty for fewer than two points", () => {
    expect(
      buildSmoothPath(
        [],
        () => 0,
        () => 0,
      ),
    ).toBe("");
    expect(
      buildSmoothPath(
        [{ v: 1 }],
        () => 0,
        () => 0,
      ),
    ).toBe("");
  });

  it("uses line segment for exactly two points", () => {
    const path = buildSmoothPath(
      [{ v: 1 }, { v: 2 }],
      (p) => p.v * 10,
      (p) => p.v * 5,
    );
    expect(path).toBe("M10.0 5.0 L20.0 10.0");
  });

  it("uses cubic curves for three or more points", () => {
    const path = buildSmoothPath(
      [{ v: 0 }, { v: 1 }, { v: 2 }],
      (p) => p.v,
      (p) => p.v,
    );
    expect(path.startsWith("M0.0 0.0 C")).toBe(true);
    expect(path).toContain("2.0 2.0");
  });
});
