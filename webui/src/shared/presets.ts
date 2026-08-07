import type { ChipOption } from "./types";

export const POWER_STOP_PRESETS: ChipOption[] = [
  { id: "80", l: "80%" },
  { id: "85", l: "85%" },
  { id: "90", l: "90%" },
  { id: "95", l: "95%" },
  { id: "100", l: "100%" },
  { id: "110", l: "关闭" },
];

export const POWER_START_PRESETS: ChipOption[] = [
  { id: "70", l: "70%" },
  { id: "75", l: "75%" },
  { id: "80", l: "80%" },
  { id: "85", l: "85%" },
  { id: "90", l: "90%" },
  { id: "95", l: "95%" },
];

export const TEMP_STOP_PRESETS: ChipOption[] = [
  { id: "45", l: "45°C" },
  { id: "50", l: "50°C" },
  { id: "55", l: "55°C" },
  { id: "60", l: "60°C" },
];

export const TEMP_START_PRESETS: ChipOption[] = [
  { id: "35", l: "35°C" },
  { id: "40", l: "40°C" },
  { id: "45", l: "45°C" },
  { id: "50", l: "50°C" },
];

export const LEVEL_PRESETS: ChipOption[] = [
  { id: "80", l: "80%" },
  { id: "85", l: "85%" },
  { id: "90", l: "90%" },
  { id: "95", l: "95%" },
  { id: "97", l: "97%" },
  { id: "110", l: "关闭" },
];

export const BYPASS_TEMP_PRESETS: ChipOption[] = [
  { id: "110", l: "关闭" },
  { id: "38", l: "38°" },
  { id: "40", l: "40°" },
  { id: "42", l: "42°" },
  { id: "45", l: "45°" },
];

/** 电流快捷：id 为微安；≥1000mA 显示为安，其余显示毫安 */
export const DEFAULT_CURRENT_PRESETS: ChipOption[] = [
  { id: "2000000", l: "2A" },
  { id: "3000000", l: "3A" },
  { id: "5000000", l: "5A" },
  { id: "6000000", l: "6A" },
  { id: "8000000", l: "8A" },
];

export const ONE_LIMIT_CURRENT_PRESETS: ChipOption[] = [
  { id: "500000", l: "500mA" },
  { id: "1000000", l: "1A" },
  { id: "1500000", l: "1.5A" },
  { id: "2000000", l: "2A" },
  { id: "3000000", l: "3A" },
];

export const SMALL_CURRENT_PRESETS: ChipOption[] = [
  { id: "100000", l: "100mA" },
  { id: "200000", l: "200mA" },
  { id: "300000", l: "300mA" },
  { id: "500000", l: "500mA" },
  { id: "1000000", l: "1A" },
];
