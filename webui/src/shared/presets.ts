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
