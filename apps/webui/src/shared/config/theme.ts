import { ThemeMode, ThemePack } from "./enums";

export const THEME_DEFAULTS = {
  pack: ThemePack.Default,
  mode: ThemeMode.System,
  accentId: "teal",
  md3Seed: "#6750A4",
  monetOn: true,
  compactOn: false,
  uiCustom: false,
  fontScale: 1,
  fontMin: 0.85,
  fontMax: 1.3,
  fontStep: 0.05,
} as const;

/** 切主题包时套用的壳层默认（仍可被「我的」覆盖） */
export const PACK_CHROME_DEFAULTS: Record<
  ThemePack,
  { floatDock: boolean; dockGlass: boolean; barBlur: boolean }
> = {
  [ThemePack.Default]: { floatDock: false, dockGlass: false, barBlur: true },
  [ThemePack.Md3]: { floatDock: false, dockGlass: false, barBlur: true },
  [ThemePack.Miuix]: { floatDock: true, dockGlass: true, barBlur: true },
};

export const THEME_SWITCH_CLASS: Record<ThemePack, string> = {
  [ThemePack.Default]: "ts-default",
  [ThemePack.Md3]: "ts-md3",
  [ThemePack.Miuix]: "ts-miuix",
};

export const THEME_SWITCH_SIZE: Record<ThemePack, string> = {
  [ThemePack.Default]: "22px",
  [ThemePack.Md3]: "32px",
  [ThemePack.Miuix]: "28px",
};

export const PACK_TOAST_LABEL: Record<ThemePack, string> = {
  [ThemePack.Default]: "默认主题",
  [ThemePack.Md3]: "Material You (MD3)",
  [ThemePack.Miuix]: "MIUIX",
};

export const PACK_HINT: Record<ThemePack, string> = {
  [ThemePack.Default]: "默认控件形态",
  [ThemePack.Md3]: "Material You 控件与布局",
  [ThemePack.Miuix]: "HyperOS 控件与悬浮底栏",
};

export const MODE_TOAST_LABEL: Record<ThemeMode, string> = {
  [ThemeMode.Light]: "浅色模式",
  [ThemeMode.Dark]: "深色模式",
  [ThemeMode.System]: "跟随系统",
};

export const THEME_CARD_CLASS: Record<ThemePack, string> = {
  [ThemePack.Default]: "",
  [ThemePack.Md3]: "md3-tonal",
  [ThemePack.Miuix]: "miuix-card",
};

export const DOCK_CLASS: Record<ThemePack, string> = {
  [ThemePack.Default]: "dock-default",
  [ThemePack.Md3]: "dock-md3",
  [ThemePack.Miuix]: "dock-miuix",
};

export const MD3_CUSTOM_ID = "custom";
