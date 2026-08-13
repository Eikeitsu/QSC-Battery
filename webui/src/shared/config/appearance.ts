import type { ChipOption } from "@/shared/types";
import { ThemeMode, ThemePack } from "./enums";
import { MD3_CUSTOM_ID, THEME_DEFAULTS } from "./theme";

export const THEME_MODE_PRESETS: ChipOption[] = [
  { id: ThemeMode.Light, l: "浅色" },
  { id: ThemeMode.Dark, l: "深色" },
  { id: ThemeMode.System, l: "跟随系统" },
];

export const PACK_PRESETS: ChipOption[] = [
  { id: ThemePack.Default, l: "默认" },
  { id: ThemePack.Md3, l: "MD3" },
  { id: ThemePack.Miuix, l: "MIUIX" },
];

export const MD3_SEED_PRESETS: ChipOption[] = [
  { id: THEME_DEFAULTS.md3Seed, l: "紫" },
  { id: "#0D9488", l: "青" },
  { id: "#1B6EF3", l: "蓝" },
  { id: "#E11D48", l: "玫" },
  { id: "#D97706", l: "橙" },
  { id: "#059669", l: "绿" },
  { id: MD3_CUSTOM_ID, l: "自定义" },
];

export const DEFAULT_ACCENTS: Record<
  string,
  { label: string; light: string; dark: string }
> = {
  teal: { label: "电弧青", light: "#0D9488", dark: "#2DD4BF" },
  ocean: { label: "海蓝", light: "#0284C7", dark: "#38BDF8" },
  violet: { label: "雾紫", light: "#7C3AED", dark: "#A78BFA" },
  amber: { label: "琥珀", light: "#D97706", dark: "#FBBF24" },
  rose: { label: "玫红", light: "#E11D48", dark: "#FB7185" },
  forest: { label: "森绿", light: "#059669", dark: "#34D399" },
};
