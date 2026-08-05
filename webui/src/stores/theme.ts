import { computed, reactive, ref } from "vue";
import { showToast } from "vant";
import { FONT_KEY } from "../shared";

const THEME_KEY = "qsc_theme_mode";
const MONET_KEY = "qsc_monet";
const COMPACT_KEY = "qsc_compact";

export type ThemeMode = "light" | "dark" | "system";
export type ResolvedTheme = "light" | "dark";

const themeMode = ref<ThemeMode>("system");
const monetOn = ref(true);
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
      if (String(color).startsWith("#")) {
        let h = String(color).slice(1);
        if (h.length === 3)
          h = h
            .split("")
            .map((c) => c + c)
            .join("");
        const n = parseInt(h, 16);
        const r = (n >> 16) & 255;
        const g = (n >> 8) & 255;
        const b = n & 255;
        const f = (v: number) => {
          const s = v / 255;
          return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
        };
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
      }
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

  function syncStatusBar(): void {
    const dark = resolved.value === "dark";
    const meta = document.querySelector('meta[name="theme-color"]');
    const bg = readCssColor("--van-background", dark ? "#0f1216" : "#eef1f5");
    if (meta) meta.setAttribute("content", bg);
    document.documentElement.style.colorScheme = dark ? "only dark" : "only light";
    const lightBars = relativeLuminance(bg) > 0.45;
    applyStatusBars(lightBars);
  }

  function applyThemeDom(): void {
    const r = resolved.value;
    document.documentElement.setAttribute("data-theme", r);
    document.documentElement.style.colorScheme =
      r === "dark" ? "only dark" : "only light";
    document.documentElement.classList.toggle("monet-on", monetOn.value);
    document.documentElement.classList.toggle("monet-off", !monetOn.value);
    document.documentElement.classList.toggle("compact-on", compactOn.value);
    document.documentElement.style.setProperty("--font-scale", String(fontScale.value));
    document.documentElement.style.fontSize = `${16 * fontScale.value}px`;
    syncStatusBar();
    requestAnimationFrame(() => syncStatusBar());
  }

  function load(): void {
    try {
      const saved = localStorage.getItem(THEME_KEY);
      themeMode.value =
        saved === "light" || saved === "dark" || saved === "system" ? saved : "system";
      const m = localStorage.getItem(MONET_KEY);
      monetOn.value = m === null ? true : m === "1";
      compactOn.value = localStorage.getItem(COMPACT_KEY) === "1";
      const s = parseFloat(localStorage.getItem(FONT_KEY) || "1");
      fontScale.value = Number.isFinite(s) ? Math.min(1.3, Math.max(0.85, s)) : 1;
    } catch {
      /* ignore */
    }
    applyThemeDom();
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
      else syncStatusBar();
    };
    if (typeof media.addEventListener === "function")
      media.addEventListener("change", onChange);
    else if (typeof media.addListener === "function") media.addListener(onChange);
  }

  return reactive({
    themeMode,
    monetOn,
    compactOn,
    fontScale,
    resolved,
    load,
    setThemeMode,
    setMonet,
    setCompact,
    setFontScale,
    bindSystemListener,
    syncStatusBar,
  });
}
