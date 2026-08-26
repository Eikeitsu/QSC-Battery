import type { ConfigKey, CurrentConfig, Settings } from "@/shared/types";
import { BinaryFlag, BypassMode } from "./enums";

export const CONFIG_KEYS: readonly ConfigKey[] = [
  "power_stop",
  "power_start",
  "power_stop_time",
  "charge_full",
  "power_reset",
  "Compatibility_mode",
  "stop_hold_wakelock",
  "notify_charge_event",
  "notify_charge_kinds",
  "temperature_switch",
  "temperature_switch_stop",
  "temperature_switch_start",
] as const;

export const DEFAULTS: Settings = {
  power_stop: "100",
  power_start: "95",
  power_stop_time: "3",
  charge_full: BinaryFlag.Off,
  power_reset: BinaryFlag.Off,
  Compatibility_mode: BinaryFlag.Off,
  stop_hold_wakelock: "auto",
  notify_charge_event: BinaryFlag.Off,
  notify_charge_kinds: "stop,resume,fail",
  temperature_switch: BinaryFlag.On,
  temperature_switch_stop: "60",
  temperature_switch_start: "50",
};

export const CURRENT_DEFAULTS: CurrentConfig = {
  current_control: 0,
  bypass_enable: 0,
  battery_stop: 110,
  bypass_temp: 110,
  bypass_schedule: [],
  slow_charge: 110,
  default_current_max: 5000000,
  temperature_current: 0,
  default_current_limit: 40,
  default_current_max_limit: 1500000,
  temperature_current_limit: 45,
  constant_current_max: 100000,
  app_limit: 0,
  app_current_max: 200000,
  app_list: [
    "com.tencent.tmgp.sgame",
    "com.tencent.tmgp.pubgmhd",
    "com.miHoYo.Yuanshen",
    "com.tencent.lolm",
  ],
  bypass_mode: BypassMode.Sim,
  safety_temp_max: 48,
  battery_current: [
    "/sys/class/power_supply/battery/fast_charge_current",
    "/sys/class/power_supply/battery/current_max",
    "/sys/class/power_supply/battery/constant_charge_current",
    "/sys/class/power_supply/battery/constant_charge_current_max",
    "/sys/class/power_supply/main/constant_charge_current_max",
  ],
  restricted: [
    "/sys/class/qcom-battery/restrict_chg value=1",
    "/sys/class/qcom-battery/restricted_charging value=1",
    "/sys/class/power_supply/battery/step_charging_enabled value=0",
  ],
  current_reaffirm_sec: 24,
  current_drift_ua: 300000,
  current_step_ua: 0,
};
