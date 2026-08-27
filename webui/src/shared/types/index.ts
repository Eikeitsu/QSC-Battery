import type { BypassMode, BadgeType } from "@/shared/config/enums";

export type ConfigKey =
  | "power_stop"
  | "power_start"
  | "power_stop_time"
  | "charge_full"
  | "power_reset"
  | "Compatibility_mode"
  | "stop_hold_wakelock"
  | "notify_charge_event"
  | "notify_charge_kinds"
  | "temperature_switch"
  | "temperature_switch_stop"
  | "temperature_switch_start"
  | "loop_interval_sec"
  | "loop_interval_maintain_sec"
  | "switch_verify_sec"
  | "wireless_policy"
  | "app_stop"
  | "app_stop_list"
  | "history_enable"
  | "history_interval_sec"
  | "power_saver"
  | "loop_interval_idle_sec"
  | "loop_interval_idle_native_sec"
  | "loop_interval_plugged_sec"
  | "loop_interval_near_window"
  | "native_daemon"
  | "native_impl"
  | "chart_show";

export type Settings = Record<ConfigKey, string>;

export interface CurrentConfig {
  current_control: number;
  /** 旁路总开关：0 关 / 1 开 */
  bypass_enable: number;
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
  bypass_mode: BypassMode;
  safety_temp_max: number;
  battery_current: unknown[];
  /** 可选；`"路径 value=值"`；空则跳过 */
  restricted: string[];
  /** 偏高时周期重申间隔（秒）；0=关 */
  current_reaffirm_sec: number;
  /** 偏高裕量（微安） */
  current_drift_ua: number;
  /** 降流台阶（微安）；0=直接写目标 */
  current_step_ua: number;
}

export interface ChipOption {
  id: string;
  l: string;
}

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
  /** 电池健康文案，如 Good / Dead */
  health: string;
  /** SOH 百分比数字字符串，无则 "--" */
  soh: string;
  designMah: string;
  fullMah: string;
  cycleCount: string;
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
