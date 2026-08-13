/** 有限集合用 TS 字符串枚举；文案/一次性 UI 不必再抽配置。 */

export enum TabName {
  Home = "home",
  Config = "config",
  Log = "log",
  More = "more",
}

export function isTabName(v: unknown): v is TabName {
  return Object.values(TabName).includes(v as TabName);
}

export enum ThemePack {
  Default = "default",
  Md3 = "md3",
  Miuix = "miuix",
}

export function isThemePack(v: unknown): v is ThemePack {
  return Object.values(ThemePack).includes(v as ThemePack);
}

export enum ThemeMode {
  Light = "light",
  Dark = "dark",
  System = "system",
}

export function isThemeMode(v: unknown): v is ThemeMode {
  return Object.values(ThemeMode).includes(v as ThemeMode);
}

/** 实际生效的深浅，不含跟随系统 */
export type ResolvedTheme = ThemeMode.Light | ThemeMode.Dark;

export enum BypassMode {
  Sim = "sim",
  Auto = "auto",
}

export function isBypassMode(v: unknown): v is BypassMode {
  return v === BypassMode.Sim || v === BypassMode.Auto;
}

export enum BadgeType {
  Default = "default",
  Primary = "primary",
  Success = "success",
  Warning = "warning",
  Danger = "danger",
}

/** conf / localStorage 里的开关位 */
export enum BinaryFlag {
  Off = "0",
  On = "1",
}
