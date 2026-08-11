/** 电池展示用文案 / 数值解析（三主题共用） */

const HEALTH_ZH: Record<string, string> = {
  Good: "良好",
  Cold: "过冷",
  Dead: "损坏",
  Overheat: "过热",
  "Over voltage": "过压",
  OverVoltage: "过压",
  "Unspecified failure": "异常",
  UnspecifiedFailure: "异常",
  Unknown: "未知",
  Warm: "偏热",
  Cool: "偏凉",
};

export function healthLabel(raw: string | undefined | null): string {
  const h = (raw || "").trim();
  if (!h || h === "--") return "--";
  return HEALTH_ZH[h] || HEALTH_ZH[h.replace(/_/g, " ")] || h;
}

export function parsePercent(raw: string | undefined | null): number | null {
  const n = Number(
    String(raw ?? "")
      .replace(/%/g, "")
      .trim(),
  );
  if (!Number.isFinite(n)) return null;
  return Math.max(0, Math.min(100, Math.round(n)));
}

export function formatMah(raw: string | undefined | null): string {
  const v = (raw || "").trim();
  if (!v || v === "--") return "--";
  return `${v} mAh`;
}

/** 满充相对设计容量的保留比例；缺数据返回 null */
export function capacityRetention(
  fullMah: string | undefined | null,
  designMah: string | undefined | null,
): number | null {
  const full = Number(String(fullMah ?? "").trim());
  const design = Number(String(designMah ?? "").trim());
  if (!Number.isFinite(full) || !Number.isFinite(design) || design <= 0) return null;
  return Math.max(0, Math.min(100, Math.round((full * 100) / design)));
}

export function isChargingLabel(chargeLabel: string | undefined | null): boolean {
  return (chargeLabel || "").trim() === "充电中";
}
