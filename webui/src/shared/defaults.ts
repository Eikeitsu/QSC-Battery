import type { ConfigKey, CurrentConfig, Settings } from "./types";

export const CONFIG_KEYS: readonly ConfigKey[] = [
  "power_stop",
  "power_start",
  "power_stop_time",
  "charge_full",
  "power_reset",
  "Compatibility_mode",
  "temperature_switch",
  "temperature_switch_stop",
  "temperature_switch_start",
] as const;

export const DEFAULTS: Settings = {
  power_stop: "100",
  power_start: "95",
  power_stop_time: "3",
  charge_full: "0",
  power_reset: "0",
  Compatibility_mode: "0",
  temperature_switch: "1",
  temperature_switch_stop: "60",
  temperature_switch_start: "50",
};

export const CURRENT_DEFAULTS: CurrentConfig = {
  current_control: 0,
  battery_stop: 110,
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
  bypass_mode: "sim",
  safety_temp_max: 48,
  battery_current: [],
};
