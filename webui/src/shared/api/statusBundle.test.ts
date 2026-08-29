import { describe, expect, it } from "vitest";
import { parseStatusBundle } from "./statusBundle";

describe("status bundle contract", () => {
  it("parses all status fields from one shell response", () => {
    const stdout = [
      "__QSC_SNAPSHOT__",
      "level=87",
      "temp=34",
      "status=2",
      "powered=1",
      "source=battery",
      "read_at=123",
      "__QSC_MODULE_OFF__",
      "0",
      "__QSC_CHARGING_STOPPED__",
      "0",
      "__QSC_DESCRIPTION__",
      "⚡充电中 | 87% ● 34°C",
      "__QSC_VOLTAGE__",
      "4200000",
      "__QSC_CURRENT__",
      "-1200000",
      "__QSC_VERSION__",
      "827",
      "__QSC_BATTERY__",
      "health=Good",
      "soh=98",
      "__QSC_FAILED__",
      "0",
    ].join("\n");

    expect(parseStatusBundle(stdout)).toMatchObject({
      snapshot: {
        level: "87",
        temp: "34",
        status: "2",
        powered: true,
      },
      moduleOff: "0",
      chargingStopped: "0",
      description: "⚡充电中 | 87% ● 34°C",
      voltage: "4200000",
      current: "-1200000",
      version: "827",
      batteryInfo: "health=Good\nsoh=98",
      failed: "0",
    });
  });

  it("does not confuse an ordinary line with a section marker", () => {
    expect(parseStatusBundle("level=10\n__QSC_DESCRIPTION__\nhello")).toMatchObject({
      description: "hello",
      snapshot: {
        level: "",
      },
    });
  });
});
