import { DEFAULTS } from "@/shared/config/defaults";
import { BinaryFlag } from "@/shared/config/enums";
import type { Settings } from "@/shared/types";
import { clampInt, clampLevelOrOff, type SanitizeResult } from "./clamp";
import { LIMITS } from "./constants";
import { PKG_RE } from "./listSanitize";

/** 停充/温控 conf 字段 */
export function sanitizeSettings(input: Settings): SanitizeResult<Settings> {
  const next: Settings = { ...input };
  let fixed = false;

  const mark = (cond: boolean) => {
    if (cond) fixed = true;
  };

  const powerStop = clampLevelOrOff(next.power_stop, Number(DEFAULTS.power_stop));
  if (String(powerStop) !== String(next.power_stop)) mark(true);
  next.power_stop = String(powerStop);

  let powerStart = clampInt(
    next.power_start,
    LIMITS.levelMin,
    LIMITS.levelMax,
    Number(DEFAULTS.power_start),
  );
  if (powerStop !== LIMITS.levelOff && powerStart >= powerStop) {
    powerStart = Math.max(LIMITS.levelMin, powerStop - 5);
    mark(true);
  }
  if (String(powerStart) !== String(input.power_start)) mark(true);
  next.power_start = String(powerStart);

  const stopTime = clampInt(
    next.power_stop_time,
    LIMITS.powerStopTimeMin,
    LIMITS.powerStopTimeMax,
    Number(DEFAULTS.power_stop_time),
  );
  if (String(stopTime) !== String(input.power_stop_time)) mark(true);
  next.power_stop_time = String(stopTime);

  next.charge_full = next.charge_full === BinaryFlag.On ? BinaryFlag.On : BinaryFlag.Off;
  {
    const mode = String(next.charge_full_mode || "auto");
    next.charge_full_mode =
      mode === "time" || mode === "current" || mode === "auto" ? mode : "auto";
  }
  if (next.charge_full_mode !== String(input.charge_full_mode || "auto")) mark(true);
  const fullWait = clampInt(
    next.charge_full_wait_sec,
    60,
    3600,
    Number(DEFAULTS.charge_full_wait_sec),
  );
  if (String(fullWait) !== String(input.charge_full_wait_sec)) mark(true);
  next.charge_full_wait_sec = String(fullWait);
  // 充满再停仅在停止电量=100 时有意义；否则强制关掉，避免 UI/行为误导
  if (next.charge_full === BinaryFlag.On && String(next.power_stop) !== "100") {
    next.charge_full = BinaryFlag.Off;
    mark(true);
  }
  next.power_reset = next.power_reset === BinaryFlag.On ? BinaryFlag.On : BinaryFlag.Off;
  next.unplug_restore =
    next.unplug_restore === BinaryFlag.Off ? BinaryFlag.Off : BinaryFlag.On;
  if (next.unplug_restore !== String(input.unplug_restore || BinaryFlag.On)) mark(true);
  next.compatibility_mode =
    next.compatibility_mode === BinaryFlag.On ? BinaryFlag.On : BinaryFlag.Off;
  const hold = String(next.stop_hold_wakelock || "auto");
  next.stop_hold_wakelock =
    hold === "0" || hold === "1" || hold === "auto" ? hold : "auto";
  if (next.stop_hold_wakelock !== String(input.stop_hold_wakelock || "auto")) mark(true);
  next.notify_charge_event =
    next.notify_charge_event === BinaryFlag.On ? BinaryFlag.On : BinaryFlag.Off;
  next.notify_power_status =
    next.notify_power_status === BinaryFlag.On ? BinaryFlag.On : BinaryFlag.Off;
  {
    const raw = String(next.notify_charge_kinds || "stop,resume,fail")
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s === "stop" || s === "resume" || s === "fail");
    const uniq = [...new Set(raw.length ? raw : ["stop", "resume", "fail"])];
    next.notify_charge_kinds = uniq.join(",");
    if (
      next.notify_charge_kinds !== String(input.notify_charge_kinds || "stop,resume,fail")
    )
      mark(true);
  }
  next.temperature_switch =
    next.temperature_switch === BinaryFlag.Off ? BinaryFlag.Off : BinaryFlag.On;

  const tempStop = clampInt(
    next.temperature_switch_stop,
    LIMITS.tempSwitchMin,
    LIMITS.tempSwitchMax,
    Number(DEFAULTS.temperature_switch_stop),
  );
  let tempStart = clampInt(
    next.temperature_switch_start,
    LIMITS.tempSwitchMin,
    LIMITS.tempSwitchMax,
    Number(DEFAULTS.temperature_switch_start),
  );
  if (tempStop <= tempStart) {
    tempStart = Math.max(LIMITS.tempSwitchMin, tempStop - 5);
    mark(true);
  }
  if (String(tempStop) !== String(input.temperature_switch_stop)) mark(true);
  if (String(tempStart) !== String(input.temperature_switch_start)) mark(true);
  next.temperature_switch_stop = String(tempStop);
  next.temperature_switch_start = String(tempStart);

  const loopN = clampInt(
    next.loop_interval_sec,
    2,
    30,
    Number(DEFAULTS.loop_interval_sec),
  );
  if (String(loopN) !== String(input.loop_interval_sec)) mark(true);
  next.loop_interval_sec = String(loopN);
  const loopM = clampInt(
    next.loop_interval_maintain_sec,
    3,
    60,
    Number(DEFAULTS.loop_interval_maintain_sec),
  );
  if (String(loopM) !== String(input.loop_interval_maintain_sec)) mark(true);
  next.loop_interval_maintain_sec = String(loopM);
  const verify = clampInt(
    next.switch_verify_sec,
    0,
    5,
    Number(DEFAULTS.switch_verify_sec),
  );
  if (String(verify) !== String(input.switch_verify_sec)) mark(true);
  next.switch_verify_sec = String(verify);
  next.switch_batch_blind =
    next.switch_batch_blind === BinaryFlag.Off ? BinaryFlag.Off : BinaryFlag.On;
  if (next.switch_batch_blind !== String(input.switch_batch_blind || BinaryFlag.On))
    mark(true);
  const wp = String(next.wireless_policy || "same");
  next.wireless_policy = wp === "ignore" ? "ignore" : "same";
  if (next.wireless_policy !== String(input.wireless_policy || "same")) mark(true);
  next.app_stop = next.app_stop === BinaryFlag.On ? BinaryFlag.On : BinaryFlag.Off;
  {
    const pkgs = String(next.app_stop_list || "")
      .split(/[,;\s]+/)
      .map((s) => s.trim())
      .filter((s) => PKG_RE.test(s))
      .slice(0, LIMITS.appListMax);
    next.app_stop_list = [...new Set(pkgs)].join(",");
    if (next.app_stop_list !== String(input.app_stop_list || "")) mark(true);
  }
  next.history_enable =
    next.history_enable === BinaryFlag.Off ? BinaryFlag.Off : BinaryFlag.On;
  const histI = clampInt(
    next.history_interval_sec,
    15,
    600,
    Number(DEFAULTS.history_interval_sec),
  );
  if (String(histI) !== String(input.history_interval_sec)) mark(true);
  next.history_interval_sec = String(histI);

  next.power_saver = next.power_saver === BinaryFlag.Off ? BinaryFlag.Off : BinaryFlag.On;
  if (next.power_saver !== String(input.power_saver || BinaryFlag.On)) mark(true);
  const idleI = clampInt(
    next.loop_interval_idle_sec,
    3,
    300,
    Number(DEFAULTS.loop_interval_idle_sec),
  );
  if (String(idleI) !== String(input.loop_interval_idle_sec)) mark(true);
  next.loop_interval_idle_sec = String(idleI);
  // 0 = 不放大；比「未插电间隔」小则模块侧不生效，这里不强改，避免抹掉用户输入
  const idleNativeI = clampInt(
    next.loop_interval_idle_native_sec,
    0,
    900,
    Number(DEFAULTS.loop_interval_idle_native_sec),
  );
  if (String(idleNativeI) !== String(input.loop_interval_idle_native_sec)) mark(true);
  next.loop_interval_idle_native_sec = String(idleNativeI);
  const plugI = clampInt(
    next.loop_interval_plugged_sec,
    2,
    120,
    Number(DEFAULTS.loop_interval_plugged_sec),
  );
  if (String(plugI) !== String(input.loop_interval_plugged_sec)) mark(true);
  next.loop_interval_plugged_sec = String(plugI);
  // 0 = 不放大；仅对支持 watch 的 Rust 版守护有效，模块侧比「插电间隔」小则不生效
  const plugNativeI = clampInt(
    next.loop_interval_plugged_native_sec,
    0,
    300,
    Number(DEFAULTS.loop_interval_plugged_native_sec),
  );
  if (String(plugNativeI) !== String(input.loop_interval_plugged_native_sec)) mark(true);
  next.loop_interval_plugged_native_sec = String(plugNativeI);
  const nearW = clampInt(
    next.loop_interval_near_window,
    1,
    20,
    Number(DEFAULTS.loop_interval_near_window),
  );
  if (String(nearW) !== String(input.loop_interval_near_window)) mark(true);
  next.loop_interval_near_window = String(nearW);

  next.native_daemon =
    next.native_daemon === BinaryFlag.Off ? BinaryFlag.Off : BinaryFlag.On;
  if (next.native_daemon !== String(input.native_daemon || BinaryFlag.On)) mark(true);
  next.native_impl =
    next.native_impl === "c" || next.native_impl === "off" ? next.native_impl : "rust";
  if (next.native_impl !== String(input.native_impl || "rust")) mark(true);

  // 曲线隐藏时采样没有意义，顺带把采样一并关掉，避免"看不见还在写盘"
  next.chart_show = next.chart_show === BinaryFlag.Off ? BinaryFlag.Off : BinaryFlag.On;
  if (next.chart_show !== String(input.chart_show || BinaryFlag.On)) mark(true);
  if (next.chart_show === BinaryFlag.Off && next.history_enable !== BinaryFlag.Off) {
    next.history_enable = BinaryFlag.Off;
    mark(true);
  }

  return { value: next, fixed };
}
