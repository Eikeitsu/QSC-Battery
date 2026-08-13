import { BinaryFlag } from "./enums";

/** WebUI localStorage 键，集中管理避免散写。 */

export const STORAGE_KEYS = {
  themePack: "qsc_theme_pack",
  themeMode: "qsc_theme_mode",
  accent: "qsc_accent",
  md3Seed: "qsc_md3_seed",
  monet: "qsc_monet",
  floatDock: "qsc_float_dock",
  dockGlass: "qsc_dock_glass",
  barBlur: "qsc_bar_blur",
  compact: "qsc_compact",
  uiCustom: "qsc_ui_custom",
  fontScale: "qsc_font_scale",
  currentCollapse: "qsc_current_collapse",
  legacyDockPage: "qsc_dock_page",
} as const;

/** @deprecated 使用 STORAGE_KEYS.fontScale */
export const FONT_KEY = STORAGE_KEYS.fontScale;

export function readStorage(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

export function writeStorage(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* ignore */
  }
}

export function removeStorage(key: string): void {
  try {
    localStorage.removeItem(key);
  } catch {
    /* ignore */
  }
}

export function writeStorageFlag(key: string, on: boolean): void {
  writeStorage(key, on ? BinaryFlag.On : BinaryFlag.Off);
}

export function readStorageFlag(key: string, defaultOn: boolean): boolean {
  const raw = readStorage(key);
  if (raw === null) return defaultOn;
  return raw === BinaryFlag.On;
}
