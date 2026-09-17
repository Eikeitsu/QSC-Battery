import { LIMITS } from "./constants";

/** 自定义毫安输入 → 合法微安；非法返回 null */
export function parseMaToUa(
  maText: string,
  maxUa = LIMITS.uaMax,
  minUa = LIMITS.uaMin,
): number | null {
  const ma = Number(String(maText ?? "").trim());
  if (!Number.isFinite(ma) || ma < 0) return null;
  const ua = Math.round(ma * 1000);
  if (ua < minUa || ua > maxUa) return null;
  return ua;
}
