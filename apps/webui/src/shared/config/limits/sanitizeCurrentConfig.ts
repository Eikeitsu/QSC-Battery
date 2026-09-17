import { CURRENT_DEFAULTS } from "@/shared/config/defaults";
import { BypassMode, isBypassMode } from "@/shared/config/enums";
import type { CurrentConfig } from "@/shared/types";
import { clampInt, clampLevelOrOff, clampUa, type SanitizeResult } from "./clamp";
import { LIMITS } from "./constants";
import {
  sanitizePackageList,
  sanitizeRestricted,
  sanitizeScheduleList,
  sanitizeSysPaths,
} from "./listSanitize";

/** current.json 全量规范化 */
export function sanitizeCurrentConfig(
  input: CurrentConfig,
): SanitizeResult<CurrentConfig> {
  const d = CURRENT_DEFAULTS;
  let fixed = false;
  const mark = (cond: boolean) => {
    if (cond) fixed = true;
  };

  const battery_stop = clampLevelOrOff(input.battery_stop, d.battery_stop);
  const bypass_temp = clampLevelOrOff(input.bypass_temp, d.bypass_temp);
  const slow_charge = clampLevelOrOff(input.slow_charge, d.slow_charge);
  mark(battery_stop !== Number(input.battery_stop));
  mark(bypass_temp !== Number(input.bypass_temp));
  mark(slow_charge !== Number(input.slow_charge));

  const defMax = clampUa(input.default_current_max, d.default_current_max);
  let cur1 = clampUa(input.default_current_max_limit, d.default_current_max_limit);
  let cur2 = clampUa(
    input.constant_current_max,
    d.constant_current_max,
    LIMITS.uaSmallMax,
  );
  let appCur = clampUa(input.app_current_max, d.app_current_max, LIMITS.uaSmallMax);
  mark(defMax !== Number(input.default_current_max));
  mark(cur1 !== Number(input.default_current_max_limit));
  mark(cur2 !== Number(input.constant_current_max));
  mark(appCur !== Number(input.app_current_max));

  // 层级：二限 ≤ 游戏 ≤ 一限 ≤ 默认上限
  if (cur1 > defMax) {
    cur1 = defMax;
    mark(true);
  }
  if (appCur > cur1) {
    appCur = cur1;
    mark(true);
  }
  if (cur2 > appCur) {
    cur2 = appCur;
    mark(true);
  }

  const limit1 = clampInt(
    input.default_current_limit,
    LIMITS.currentTempMin,
    LIMITS.currentTempMax,
    d.default_current_limit,
  );
  let limit2 = clampInt(
    input.temperature_current_limit,
    LIMITS.currentTempMin,
    LIMITS.currentTempMax,
    d.temperature_current_limit,
  );
  if (limit2 <= limit1) {
    limit2 = Math.min(LIMITS.currentTempMax, limit1 + 5);
    mark(true);
  }
  mark(limit1 !== Number(input.default_current_limit));
  mark(limit2 !== Number(input.temperature_current_limit));

  const safety = clampInt(
    input.safety_temp_max,
    LIMITS.safetyTempMin,
    LIMITS.safetyTempMax,
    d.safety_temp_max,
  );
  mark(safety !== Number(input.safety_temp_max));

  const app_list = sanitizePackageList(input.app_list);
  const bypass_schedule = sanitizeScheduleList(input.bypass_schedule);
  const battery_current = sanitizeSysPaths(
    input.battery_current,
    d.battery_current as string[],
  );
  const restricted = sanitizeRestricted(input.restricted, d.restricted as string[]);
  if (app_list.length !== (input.app_list?.length || 0)) mark(true);
  if (bypass_schedule.length !== (input.bypass_schedule?.length || 0)) mark(true);

  const reaffirm = clampInt(
    input.current_reaffirm_sec,
    LIMITS.reaffirmSecMin,
    LIMITS.reaffirmSecMax,
    d.current_reaffirm_sec,
  );
  const drift = clampInt(
    input.current_drift_ua,
    LIMITS.driftUaMin,
    LIMITS.driftUaMax,
    d.current_drift_ua,
  );
  const step = clampInt(
    input.current_step_ua,
    LIMITS.stepUaMin,
    LIMITS.stepUaMax,
    d.current_step_ua,
  );
  mark(reaffirm !== Number(input.current_reaffirm_sec ?? d.current_reaffirm_sec));
  mark(drift !== Number(input.current_drift_ua ?? d.current_drift_ua));
  mark(step !== Number(input.current_step_ua ?? d.current_step_ua));

  return {
    fixed,
    value: {
      current_control: Number(input.current_control) ? 1 : 0,
      bypass_enable: Number(input.bypass_enable) ? 1 : 0,
      battery_stop,
      bypass_temp,
      bypass_schedule,
      slow_charge,
      default_current_max: defMax,
      temperature_current: Number(input.temperature_current) ? 1 : 0,
      default_current_limit: limit1,
      default_current_max_limit: cur1,
      temperature_current_limit: limit2,
      constant_current_max: cur2,
      app_limit: Number(input.app_limit) ? 1 : 0,
      app_current_max: appCur,
      app_list,
      bypass_mode: isBypassMode(input.bypass_mode) ? input.bypass_mode : BypassMode.Sim,
      safety_temp_max: safety,
      battery_current,
      restricted,
      current_reaffirm_sec: reaffirm,
      current_drift_ua: drift,
      current_step_ua: step,
    },
  };
}
