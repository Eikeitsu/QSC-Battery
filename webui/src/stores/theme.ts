import { computed, ref } from "vue";
import { defineStore } from "pinia";
import { showToast } from "vant";
import {
  BinaryFlag,
  DEFAULT_ACCENTS,
  MODE_TOAST_LABEL,
  PACK_CHROME_DEFAULTS,
  PACK_TOAST_LABEL,
  STORAGE_KEYS,
  THEME_DEFAULTS,
  ThemeMode,
  ThemePack,
  type ResolvedTheme,
  isThemeMode,
  isThemePack,
  readStorage,
  readStorageFlag,
  writeStorage,
  writeStorageFlag,
} from "@/shared";
import { deriveFromSeed, normalizeHex, relativeLuminanceHex } from "@/shared/lib/color";

export type { ThemeMode, ThemePack, ResolvedTheme };

export const useTheme = defineStore("theme", () => {
  const themePack = ref<ThemePack>(THEME_DEFAULTS.pack);
  const themeMode = ref<ThemeMode>(THEME_DEFAULTS.mode);
  const accentId = ref<string>(THEME_DEFAULTS.accentId);
  const md3Seed = ref<string>(THEME_DEFAULTS.md3Seed);
  const monetOn = ref<boolean>(THEME_DEFAULTS.monetOn);
  const floatDock = ref<boolean>(PACK_CHROME_DEFAULTS[THEME_DEFAULTS.pack].floatDock);
  const dockGlass = ref<boolean>(PACK_CHROME_DEFAULTS[THEME_DEFAULTS.pack].dockGlass);
  const barBlur = ref<boolean>(PACK_CHROME_DEFAULTS[THEME_DEFAULTS.pack].barBlur);
  const compactOn = ref<boolean>(THEME_DEFAULTS.compactOn);
  const fontScale = ref<number>(THEME_DEFAULTS.fontScale);
  const uiCustom = ref<boolean>(THEME_DEFAULTS.uiCustom);

  const resolved = computed<ResolvedTheme>(() => {
    if (themeMode.value === ThemeMode.Light || themeMode.value === ThemeMode.Dark) {
      return themeMode.value;
    }
    return window.matchMedia("(prefers-color-scheme: dark)").matches
      ? ThemeMode.Dark
      : ThemeMode.Light;
  });

  function readCssColor(name: string, fallback: string): string {
    const raw = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return raw || fallback;
  }

  function relativeLuminance(color: string): number {
    const m = String(color || "")
      .trim()
      .match(/rgba?\(\s*([\d.]+)\s*,?\s*([\d.]+)\s*,?\s*([\d.]+)/i);
    if (!m) {
      if (String(color).startsWith("#")) return relativeLuminanceHex(color);
      return 0.5;
    }
    const f = (v: string) => {
      const s = Number(v) / 255;
      return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * f(m[1]) + 0.7152 * f(m[2]) + 0.0722 * f(m[3]);
  }

  function applyStatusBars(lightBars: boolean): void {
    const apply = (api: StatusBarApi | undefined): boolean => {
      if (!api || typeof api.setLightStatusBars !== "function") return false;
      try {
        api.setLightStatusBars(lightBars);
        if (typeof api.setLightNavigationBars === "function") {
          api.setLightNavigationBars(lightBars);
        }
        return true;
      } catch {
        return false;
      }
    };
    if (apply(window.$QSC_Battery) || apply(window.mmrl) || apply(window.ksu)) {
      return;
    }
    try {
      Object.keys(window).forEach((k) => {
        if (k && k.charAt(0) === "$") {
          apply((window as unknown as Record<string, StatusBarApi | undefined>)[k]);
        }
      });
    } catch {
      /* ignore */
    }
  }

  function clearInlineOverrides(): void {
    const root = document.documentElement;
    [
      "--qsc-primary",
      "--qsc-primary-soft",
      "--qsc-on-primary",
      "--qsc-primary-container",
      "--qsc-bg",
      "--qsc-surface",
      "--qsc-surface-2",
      "--qsc-text",
      "--qsc-text-2",
      "--qsc-text-3",
    ].forEach((p) => root.style.removeProperty(p));
  }

  function applyAccentVars(): void {
    const root = document.documentElement;
    const dark = resolved.value === ThemeMode.Dark;
    clearInlineOverrides();

    if (themePack.value === ThemePack.Miuix && monetOn.value) {
      // 莫奈：交给 CSS 映射宿主 --primary / --background
      return;
    }

    if (themePack.value === ThemePack.Md3) {
      const d = deriveFromSeed(md3Seed.value, dark);
      root.style.setProperty("--qsc-primary", d.primary);
      root.style.setProperty("--qsc-primary-soft", d.primarySoft);
      root.style.setProperty("--qsc-on-primary", d.onPrimary);
      root.style.setProperty("--qsc-primary-container", d.container);
      return;
    }

    // default 包色板
    const accent =
      DEFAULT_ACCENTS[accentId.value] || DEFAULT_ACCENTS[THEME_DEFAULTS.accentId];
    const primary = dark ? accent.dark : accent.light;
    root.style.setProperty("--qsc-primary", primary);
    root.style.setProperty(
      "--qsc-primary-soft",
      `color-mix(in srgb, ${primary} ${dark ? 18 : 14}%, transparent)`,
    );
    root.style.setProperty("--qsc-on-primary", dark ? "#0A1214" : "#FFFFFF");
  }

  function restorePinnedInsets(): void {
    if (typeof document === "undefined") return;
    const root = document.documentElement;
    const pinnedTop = root.style.getPropertyValue("--qsc-inset-top-pinned").trim();
    const pinnedBottom = root.style.getPropertyValue("--qsc-inset-bottom-pinned").trim();
    if (pinnedTop) root.style.setProperty("--qsc-inset-top", pinnedTop);
    if (pinnedBottom) root.style.setProperty("--qsc-inset-bottom", pinnedBottom);
  }

  /** 测量并钉死安全区。force 时允许旋转/回前台后重测。 */
  function pinSafeInsets(force = false): void {
    if (typeof document === "undefined" || !document.body) return;
    const root = document.documentElement;
    if (force) {
      root.style.removeProperty("--qsc-inset-top-pinned");
      root.style.removeProperty("--qsc-inset-bottom-pinned");
    }

    const probe = document.createElement("div");
    probe.setAttribute("aria-hidden", "true");
    probe.style.cssText =
      "position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;" +
      "padding-top:var(--window-inset-top, env(safe-area-inset-top, 0px));" +
      "padding-bottom:var(--window-inset-bottom, env(safe-area-inset-bottom, 0px));";
    document.body.appendChild(probe);
    const cs = getComputedStyle(probe);
    const top = cs.paddingTop;
    const bottom = cs.paddingBottom;
    document.body.removeChild(probe);

    const pinnedTop = root.style.getPropertyValue("--qsc-inset-top-pinned").trim();
    const pinnedBottom = root.style.getPropertyValue("--qsc-inset-bottom-pinned").trim();

    // 下拉/overscroll 回弹时 WebView 常短暂报 0：已有钉值则只恢复
    if (top && top !== "0px") {
      root.style.setProperty("--qsc-inset-top", top);
      root.style.setProperty("--qsc-inset-top-pinned", top);
    } else if (pinnedTop) {
      root.style.setProperty("--qsc-inset-top", pinnedTop);
    }

    if (bottom && bottom !== "0px") {
      root.style.setProperty("--qsc-inset-bottom", bottom);
      root.style.setProperty("--qsc-inset-bottom-pinned", bottom);
    } else if (pinnedBottom) {
      root.style.setProperty("--qsc-inset-bottom", pinnedBottom);
    }
  }

  function scheduleInsetRestore(): void {
    restorePinnedInsets();
    requestAnimationFrame(() => restorePinnedInsets());
    window.setTimeout(() => restorePinnedInsets(), 50);
    window.setTimeout(() => restorePinnedInsets(), 200);
    window.setTimeout(() => restorePinnedInsets(), 450);
    window.setTimeout(() => restorePinnedInsets(), 700);
  }

  function syncSystemChrome(): void {
    const dark = resolved.value === ThemeMode.Dark;
    const meta = document.querySelector('meta[name="theme-color"]');
    // 与页面底色一致，避免状态栏/按键栏露白或断层
    const bg = readCssColor("--qsc-bg", dark ? "#0F1216" : "#EEF1F5");
    if (meta) meta.setAttribute("content", bg);
    document.documentElement.style.backgroundColor = bg;
    if (document.body) document.body.style.backgroundColor = bg;
    document.documentElement.style.colorScheme = dark ? "only dark" : "only light";
    const lightBars = relativeLuminance(bg) > 0.45;
    applyStatusBars(lightBars);
    pinSafeInsets(false);
  }

  function applyThemeDom(): void {
    const root = document.documentElement;
    const r = resolved.value;
    root.setAttribute("data-theme", r);
    root.setAttribute("data-pack", themePack.value);
    const isMiuix = themePack.value === ThemePack.Miuix;
    root.classList.toggle("monet-on", isMiuix && monetOn.value);
    root.classList.toggle("monet-off", !(isMiuix && monetOn.value));
    for (const pack of Object.values(ThemePack)) {
      root.classList.toggle(`pack-${pack}`, themePack.value === pack);
    }
    root.classList.toggle("float-dock", isMiuix && floatDock.value);
    root.classList.toggle("dock-glass", isMiuix && dockGlass.value);
    root.classList.toggle("bar-blur", barBlur.value);
    root.classList.toggle("compact-on", compactOn.value);
    root.style.setProperty("--font-scale", String(fontScale.value));
    // 页面大量写死 px；用 zoom 统一缩放
    const appEl = document.getElementById("app");
    if (appEl) {
      (appEl.style as CSSStyleDeclaration & { zoom?: string }).zoom = String(
        fontScale.value,
      );
    }
    applyAccentVars();
    // 同步 van 主色
    root.style.setProperty("--van-primary-color", "var(--qsc-primary)");
    syncSystemChrome();
  }

  function load(): void {
    const pack = readStorage(STORAGE_KEYS.themePack);
    themePack.value = isThemePack(pack) ? pack : THEME_DEFAULTS.pack;
    const savedMode = readStorage(STORAGE_KEYS.themeMode);
    themeMode.value = isThemeMode(savedMode) ? savedMode : THEME_DEFAULTS.mode;
    const a = readStorage(STORAGE_KEYS.accent);
    accentId.value = a && DEFAULT_ACCENTS[a] ? a : THEME_DEFAULTS.accentId;
    md3Seed.value = normalizeHex(
      readStorage(STORAGE_KEYS.md3Seed) || THEME_DEFAULTS.md3Seed,
      THEME_DEFAULTS.md3Seed,
    );
    monetOn.value = readStorageFlag(STORAGE_KEYS.monet, THEME_DEFAULTS.monetOn);
    floatDock.value = readStorage(STORAGE_KEYS.floatDock) !== BinaryFlag.Off;
    dockGlass.value = readStorage(STORAGE_KEYS.dockGlass) !== BinaryFlag.Off;
    barBlur.value = readStorage(STORAGE_KEYS.barBlur) !== BinaryFlag.Off;
    compactOn.value = readStorageFlag(STORAGE_KEYS.compact, THEME_DEFAULTS.compactOn);
    uiCustom.value = readStorageFlag(STORAGE_KEYS.uiCustom, THEME_DEFAULTS.uiCustom);
    const s = parseFloat(
      readStorage(STORAGE_KEYS.fontScale) || String(THEME_DEFAULTS.fontScale),
    );
    fontScale.value = Number.isFinite(s)
      ? Math.min(THEME_DEFAULTS.fontMax, Math.max(THEME_DEFAULTS.fontMin, s))
      : THEME_DEFAULTS.fontScale;
    applyThemeDom();
  }

  function setThemePack(pack: string | number, toast = true): void {
    const next = isThemePack(pack) ? pack : THEME_DEFAULTS.pack;
    themePack.value = next;
    writeStorage(STORAGE_KEYS.themePack, next);
    const chrome = PACK_CHROME_DEFAULTS[next];
    floatDock.value = chrome.floatDock;
    dockGlass.value = chrome.dockGlass;
    barBlur.value = chrome.barBlur;
    writeStorageFlag(STORAGE_KEYS.floatDock, chrome.floatDock);
    writeStorageFlag(STORAGE_KEYS.dockGlass, chrome.dockGlass);
    writeStorageFlag(STORAGE_KEYS.barBlur, chrome.barBlur);
    applyThemeDom();
    if (toast) showToast(`已切换为${PACK_TOAST_LABEL[next]}`);
  }

  function setThemeMode(mode: string | number, toast = true): void {
    const next = isThemeMode(mode) ? mode : THEME_DEFAULTS.mode;
    themeMode.value = next;
    writeStorage(STORAGE_KEYS.themeMode, next);
    applyThemeDom();
    if (toast) showToast(`已切换为${MODE_TOAST_LABEL[next]}`);
  }

  function setAccent(id: string | number, toast = true): void {
    const key = String(id);
    accentId.value = DEFAULT_ACCENTS[key] ? key : THEME_DEFAULTS.accentId;
    writeStorage(STORAGE_KEYS.accent, accentId.value);
    applyThemeDom();
    if (toast) showToast(`已切换${DEFAULT_ACCENTS[accentId.value].label}`);
  }

  function setMd3Seed(hex: string | number, toast = true): void {
    md3Seed.value = normalizeHex(String(hex), THEME_DEFAULTS.md3Seed);
    writeStorage(STORAGE_KEYS.md3Seed, md3Seed.value);
    applyThemeDom();
    if (toast) showToast("已更新 MD3 色值");
  }

  function setMonet(on: boolean, toast = true): void {
    monetOn.value = !!on;
    writeStorageFlag(STORAGE_KEYS.monet, on);
    applyThemeDom();
    if (toast) showToast(on ? "已开启莫奈取色" : "已关闭莫奈取色");
  }

  function setFloatDock(on: boolean, toast = true): void {
    floatDock.value = !!on;
    writeStorageFlag(STORAGE_KEYS.floatDock, on);
    applyThemeDom();
    if (toast) showToast(on ? "已开启悬浮底栏" : "已关闭悬浮底栏");
  }

  function setDockGlass(on: boolean, toast = true): void {
    dockGlass.value = !!on;
    writeStorageFlag(STORAGE_KEYS.dockGlass, on);
    applyThemeDom();
    if (toast) showToast(on ? "已开启液态玻璃" : "已关闭液态玻璃");
  }

  function setBarBlur(on: boolean, toast = true): void {
    barBlur.value = !!on;
    writeStorageFlag(STORAGE_KEYS.barBlur, on);
    applyThemeDom();
    if (toast) showToast(on ? "已开启栏位模糊" : "已关闭栏位模糊");
  }

  function setCompact(on: boolean, toast = true): void {
    compactOn.value = !!on;
    writeStorageFlag(STORAGE_KEYS.compact, on);
    applyThemeDom();
    if (toast) showToast(on ? "已开启紧凑显示" : "已关闭紧凑显示");
  }

  function setUiCustom(on: boolean, toast = true): void {
    uiCustom.value = !!on;
    writeStorageFlag(STORAGE_KEYS.uiCustom, on);
    if (toast) showToast(on ? "已开启自定义外观" : "已关闭自定义外观");
  }

  function setFontScale(v: number | string, toast = false): void {
    fontScale.value = Math.min(
      THEME_DEFAULTS.fontMax,
      Math.max(THEME_DEFAULTS.fontMin, Number(v) || THEME_DEFAULTS.fontScale),
    );
    writeStorage(STORAGE_KEYS.fontScale, String(fontScale.value));
    applyThemeDom();
    if (toast) showToast("字体大小已更新");
  }

  function bindSystemListener(): void {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => {
      if (themeMode.value === ThemeMode.System) applyThemeDom();
      else syncSystemChrome();
    };
    if (typeof media.addEventListener === "function")
      media.addEventListener("change", onChange);
    else if (typeof media.addListener === "function") media.addListener(onChange);

    // 全局：下拉回弹 / visualViewport 抖动后恢复已钉死的安全区
    const onViewportGlitch = () => restorePinnedInsets();
    const vv = window.visualViewport;
    if (vv) {
      vv.addEventListener("resize", onViewportGlitch);
    }
    window.addEventListener("orientationchange", () => {
      window.setTimeout(() => pinSafeInsets(true), 300);
    });
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) {
        window.setTimeout(() => pinSafeInsets(true), 100);
      }
    });
  }

  const accentOptions = computed(() =>
    Object.entries(DEFAULT_ACCENTS).map(([id, v]) => ({ id, l: v.label })),
  );

  return {
    themePack,
    themeMode,
    accentId,
    md3Seed,
    monetOn,
    floatDock,
    dockGlass,
    barBlur,
    compactOn,
    uiCustom,
    fontScale,
    resolved,
    accentOptions,
    load,
    setThemePack,
    setThemeMode,
    setAccent,
    setMd3Seed,
    setMonet,
    setFloatDock,
    setDockGlass,
    setBarBlur,
    setCompact,
    setUiCustom,
    setFontScale,
    bindSystemListener,
    syncStatusBar: syncSystemChrome,
    restoreChromeInsets: scheduleInsetRestore,
  };
});
