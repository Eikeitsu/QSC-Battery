export type ConfigKey =
  | "power_stop"
  | "power_start"
  | "power_stop_time"
  | "charge_full"
  | "power_reset"
  | "Compatibility_mode"
  | "temperature_switch"
  | "temperature_switch_stop"
  | "temperature_switch_start";

export type Settings = Record<ConfigKey, string>;

export interface CurrentConfig {
  current_control: number;
  battery_stop: number;
  bypass_temp: number;
  bypass_schedule: string[];
  slow_charge: number;
  default_current_max: number;
  temperature_current: number;
  default_current_limit: number;
  default_current_max_limit: number;
  temperature_current_limit: number;
  constant_current_max: number;
  app_limit: number;
  app_current_max: number;
  app_list: string[];
  bypass_mode: "sim" | "auto";
  safety_temp_max: number;
  battery_current: unknown[];
}

export interface ChipOption {
  id: string;
  l: string;
}

export type BadgeType = "default" | "primary" | "success" | "warning" | "danger";

export interface StatusState {
  level: string;
  temp: string;
  badge: string;
  badgeType: BadgeType;
  desc: string;
  chargeLabel: string;
  voltage: string;
  currentMa: string;
  version: string;
  updatedAt: string;
  moduleOn: boolean;
}

export interface AppEntry {
  package: string;
  name: string;
  iconUrl: string;
}

export interface ExecResult {
  errno: number;
  stdout: string;
  stderr: string;
}

export type TabName = "home" | "config" | "log" | "more";
