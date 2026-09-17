import { LIMITS } from "./constants";

export function clampInt(n: unknown, min: number, max: number, fallback: number): number {
  const v = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(v)) return fallback;
  return Math.min(max, Math.max(min, Math.round(v)));
}

/** 1–100 有效阈值，或 110=关闭 */
export function clampLevelOrOff(n: unknown, fallback: number = LIMITS.levelOff): number {
  const v = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(v)) return fallback;
  const r = Math.round(v);
  if (r === LIMITS.levelOff) return LIMITS.levelOff;
  if (r < LIMITS.levelMin || r > LIMITS.levelMax) return fallback;
  return r;
}

export function clampUa(
  n: unknown,
  fallback: number,
  max: number = LIMITS.uaMax,
  min: number = LIMITS.uaMin,
): number {
  return clampInt(n, min, max, fallback);
}

export type SanitizeResult<T> = { value: T; fixed: boolean };
