import { describe, expect, it } from "vitest";
import { parseBatterySnapshot } from "./batterySnapshot";

describe("battery snapshot contract", () => {
  it("parses the shared shell snapshot without changing source metadata", () => {
    expect(
      parseBatterySnapshot(
        "level=100\ntemp=32\nstatus=5\npowered=1\nsource=battery\nread_at=123\n",
      ),
    ).toEqual({
      level: "100",
      temp: "32",
      status: "5",
      powered: true,
      source: "battery",
      readAt: "123",
    });
  });

  it("keeps missing fields explicit for fallback diagnostics", () => {
    expect(parseBatterySnapshot("source=fallback\n")).toMatchObject({
      level: "",
      temp: "",
      status: "",
      powered: false,
      source: "fallback",
    });
  });
});
