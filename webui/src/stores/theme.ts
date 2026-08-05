import { computed, reactive, ref } from "vue";
import { showToast } from "vant";
import { FONT_KEY } from "../shared";
import {
  DEFAULT_ACCENTS,
  deriveFromSeed,
  normalizeHex,
  relativeLuminanceHex,
} from "../shared/color";

const PACK_KEY = "qsc_theme_pack";
const THEME_KEY = "qsc_theme_mode";
const ACCENT_KEY = "qsc_accent";
const MD3_SEED_KEY = "qsc_md3_seed";
const MONET_KEY = "qsc_monet";
const FLOAT_KEY = "qsc_float_dock";
const GLASS_KEY = "qsc_dock_glass";
const BAR_BLUR_KEY = "qsc_bar_blur";
const COMPACT_KEY = "qsc_compact";

export type ThemeMode = "light" | "dark" | "system";
export type ResolvedTheme = "light" | "dark";
export type ThemePack = "default" | "md3" | "miuix";

const themePack = ref<ThemePack>("default");
const themeMode = ref<ThemeMode>("system");
const accentId = ref("teal");
const md3Seed = ref("#6750A4");
const monetOn = ref(true);
const floatDock = ref(true);
const dockGlass = ref(true);
const barBlur = ref(true);
const compactOn = ref(false);
const fontScale = ref(1);

export function useTheme() {
  const resolved = computed<ResolvedTheme>(() => {
    if (themeMode.value === "light" || themeMode.value === "dark") {
      return themeMode.value;
    }
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
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
    const dark = resolved.value === "dark";
    clearInlineOverrides();

    if (themePack.value === "miuix" && monetOn.value) {
      // 莫奈：交给 CSS 映射宿主 --primary / --background
      return;
    }

    if (themePack.value === "md3") {
      const d = deriveFromSeed(md3Seed.value, dark);
      root.style.setProperty("--qsc-primary", d.primary);
      root.style.setProperty("--qsc-primary-soft", d.primarySoft);
      root.style.setProperty("--qsc-on-primary", d.onPrimary);
      root.style.setProperty("--qsc-primary-container", d.container);
      return;
    }

    // default 包色板
    const accent = DEFAULT_ACCENTS[accentId.value] || DEFAULT_ACCENTS.teal;
    const primary = dark ? accent.dark : accent.light;
    root.style.setProperty("--qsc-primary", primary);
    root.style.setProperty(
      "--qsc-primary-soft",
      `color-mix(in srgb, ${primary} ${dark ? 18 : 14}%, transparent)`,
    );
    root.style.setProperty("--qsc-on-primary", dark ? "#0A1214" : "#FFFFFF");
  }

  function syncSystemChrome(): void {
    const dark = resolved.value === "dark";
    const meta = document.querySelector('meta[name="theme-color"]');
    // 与页面底色一致，避免状态栏/按键栏露白或断层
    const bg = readCssColor("--qsc-bg", dark ? "#0F1216" : "#EEF1F5");
    if (meta) meta.setAttribute("content", bg);
    document.documentElement.style.backgroundColor = bg;
    if (document.body) document.body.style.backgroundColor = bg;
    document.documentElement.style.colorScheme = dark ? "only dark" : "only light";
    const lightBars = relativeLuminance(bg) > 0.45;
    applyStatusBars(lightBars);
  }

  function applyThemeDom(): void {
    const root = document.documentElement;
    const r = resolved.value;
    root.setAttribute("data-theme", r);
    root.setAttribute("data-pack", themePack.value);
    root.classList.toggle("monet-on", themePack.value === "miuix" && monetOn.value);
    root.classList.toggle("monet-off", !(themePack.value === "miuix" && monetOn.value));
    root.classList.toggle("pack-default", themePack.value === "default");
    root.classList.toggle("pack-md3", themePack.value === "md3");
    root.classList.toggle("pack-miuix", themePack.value === "miuix");
    root.classList.toggle("float-dock", themePack.value === "miuix" && floatDock.value);
    root.classList.toggle("dock-glass", themePack.value === "miuix" && dockGlass.value);
    root.classList.toggle("bar-blur", barBlur.value);
    root.classList.toggle("compact-on", compactOn.value);
    root.style.setProperty("--font-scale", String(fontScale.value));
    root.style.fontSize = `${16 * fontScale.value}px`;
    applyAccentVars();
    // 同步 van 主色
    root.style.setProperty("--van-primary-color", "var(--qsc-primary)");
    syncSystemChrome();
    requestAnimationFrame(() => syncSystemChrome());
    window.setTimeout(() => syncSystemChrome(), 120);
    window.setTimeout(() => syncSystemChrome(), 480);
  }

  function load(): void {
    try {
      const pack = localStorage.getItem(PACK_KEY);
      themePack.value =
        pack === "md3" || pack === "miuix" || pack === "default" ? pack : "default";
      const saved = localStorage.getItem(THEME_KEY);
      themeMode.value =
        saved === "light" || saved === "dark" || saved === "system" ? saved : "system";
      const a = localStorage.getItem(ACCENT_KEY);
      accentId.value = a && DEFAULT_ACCENTS[a] ? a : "teal";
      md3Seed.value = normalizeHex(
        localStorage.getItem(MD3_SEED_KEY) || "#6750A4",
        "#6750A4",
      );
      const m = localStorage.getItem(MONET_KEY);
      monetOn.value = m === null ? true : m === "1";
      floatDock.value = localStorage.getItem(FLOAT_KEY) !== "0";
      dockGlass.value = localStorage.getItem(GLASS_KEY) !== "0";
      barBlur.value = localStorage.getItem(BAR_BLUR_KEY) !== "0";
      compactOn.value = localStorage.getItem(COMPACT_KEY) === "1";
      const s = parseFloat(localStorage.getItem(FONT_KEY) || "1");
      fontScale.value = Number.isFinite(s) ? Math.min(1.3, Math.max(0.85, s)) : 1;
    } catch {
      /* ignore */
    }
    applyThemeDom();
  }

  function setThemePack(pack: string | number, toast = true): void {
    const next: ThemePack =
      pack === "md3" || pack === "miuix" || pack === "default" ? pack : "default";
    themePack.value = next;
    try {
      localStorage.setItem(PACK_KEY, next);
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) {
      const labels: Record<ThemePack, string> = {
        default: "默认主题",
        md3: "Material You (MD3)",
        miuix: "MIUIX",
      };
      showToast(`已切换为${labels[next]}`);
    }
  }

  function setThemeMode(mode: string | number, toast = true): void {
    const raw = String(mode);
    const next: ThemeMode = ["light", "dark", "system"].includes(raw)
      ? (raw as ThemeMode)
      : "system";
    themeMode.value = next;
    try {
      localStorage.setItem(THEME_KEY, next);
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) {
      const labels: Record<ThemeMode, string> = {
        light: "浅色模式",
        dark: "深色模式",
        system: "跟随系统",
      };
      showToast(`已切换为${labels[next]}`);
    }
  }

  function setAccent(id: string | number, toast = true): void {
    const key = String(id);
    accentId.value = DEFAULT_ACCENTS[key] ? key : "teal";
    try {
      localStorage.setItem(ACCENT_KEY, accentId.value);
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) showToast(`已切换${DEFAULT_ACCENTS[accentId.value].label}`);
  }

  function setMd3Seed(hex: string | number, toast = true): void {
    md3Seed.value = normalizeHex(String(hex), "#6750A4");
    try {
      localStorage.setItem(MD3_SEED_KEY, md3Seed.value);
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) showToast("已更新 MD3 色值");
  }

  function setMonet(on: boolean, toast = true): void {
    monetOn.value = !!on;
    try {
      localStorage.setItem(MONET_KEY, on ? "1" : "0");
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) showToast(on ? "已开启莫奈取色" : "已关闭莫奈取色");
  }

  function setFloatDock(on: boolean, toast = true): void {
    floatDock.value = !!on;
    try {
      localStorage.setItem(FLOAT_KEY, on ? "1" : "0");
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) showToast(on ? "已开启悬浮底栏" : "已关闭悬浮底栏");
  }

  function setDockGlass(on: boolean, toast = true): void {
    dockGlass.value = !!on;
    try {
      localStorage.setItem(GLASS_KEY, on ? "1" : "0");
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) showToast(on ? "已开启液态玻璃" : "已关闭液态玻璃");
  }

  function setBarBlur(on: boolean, toast = true): void {
    barBlur.value = !!on;
    try {
      localStorage.setItem(BAR_BLUR_KEY, on ? "1" : "0");
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) showToast(on ? "已开启栏位模糊" : "已关闭栏位模糊");
  }

  function setCompact(on: boolean, toast = true): void {
    compactOn.value = !!on;
    try {
      localStorage.setItem(COMPACT_KEY, on ? "1" : "0");
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) showToast(on ? "已开启紧凑显示" : "已关闭紧凑显示");
  }

  function setFontScale(v: number | string, toast = false): void {
    fontScale.value = Math.min(1.3, Math.max(0.85, Number(v) || 1));
    try {
      localStorage.setItem(FONT_KEY, String(fontScale.value));
    } catch {
      /* ignore */
    }
    applyThemeDom();
    if (toast) showToast("字体大小已更新");
  }

  function bindSystemListener(): void {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => {
      if (themeMode.value === "system") applyThemeDom();
      else syncSystemChrome();
    };
    if (typeof media.addEventListener === "function")
      media.addEventListener("change", onChange);
    else if (typeof media.addListener === "function") media.addListener(onChange);
  }

  const accentOptions = computed(() =>
    Object.entries(DEFAULT_ACCENTS).map(([id, v]) => ({ id, l: v.label })),
  );

  return reactive({
    themePack,
    themeMode,
    accentId,
    md3Seed,
    monetOn,
    floatDock,
    dockGlass,
    barBlur,
    compactOn,
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
    setFontScale,
    bindSystemListener,
    syncStatusBar: syncSystemChrome,
  });
}
