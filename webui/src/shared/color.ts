/** 简易色相工具：用于 default 色板与 MD3 种子色 */

export function normalizeHex(input: string, fallback = "#0D9488"): string {
  let h = String(input || "").trim();
  if (!h.startsWith("#")) h = `#${h}`;
  if (/^#[0-9a-fA-F]{3}$/.test(h)) {
    h = `#${h[1]}${h[1]}${h[2]}${h[2]}${h[3]}${h[3]}`;
  }
  return /^#[0-9a-fA-F]{6}$/.test(h) ? h.toUpperCase() : fallback;
}

export function hexToRgb(hex: string): { r: number; g: number; b: number } {
  const h = normalizeHex(hex).slice(1);
  return {
    r: parseInt(h.slice(0, 2), 16),
    g: parseInt(h.slice(2, 4), 16),
    b: parseInt(h.slice(4, 6), 16),
  };
}

export function rgbToHex(r: number, g: number, b: number): string {
  const c = (n: number) =>
    Math.max(0, Math.min(255, Math.round(n)))
      .toString(16)
      .padStart(2, "0");
  return `#${c(r)}${c(g)}${c(b)}`.toUpperCase();
}

export function hexToHsl(hex: string): { h: number; s: number; l: number } {
  const { r, g, b } = hexToRgb(hex);
  const R = r / 255;
  const G = g / 255;
  const B = b / 255;
  const max = Math.max(R, G, B);
  const min = Math.min(R, G, B);
  const l = (max + min) / 2;
  if (max === min) return { h: 0, s: 0, l };
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h = 0;
  switch (max) {
    case R:
      h = ((G - B) / d + (G < B ? 6 : 0)) / 6;
      break;
    case G:
      h = ((B - R) / d + 2) / 6;
      break;
    default:
      h = ((R - G) / d + 4) / 6;
  }
  return { h: h * 360, s, l };
}

function hue2rgb(p: number, q: number, t: number): number {
  let T = t;
  if (T < 0) T += 1;
  if (T > 1) T -= 1;
  if (T < 1 / 6) return p + (q - p) * 6 * T;
  if (T < 1 / 2) return q;
  if (T < 2 / 3) return p + (q - p) * (2 / 3 - T) * 6;
  return p;
}

export function hslToHex(h: number, s: number, l: number): string {
  const H = (((h % 360) + 360) % 360) / 360;
  if (s === 0) {
    const v = l * 255;
    return rgbToHex(v, v, v);
  }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  return rgbToHex(
    hue2rgb(p, q, H + 1 / 3) * 255,
    hue2rgb(p, q, H) * 255,
    hue2rgb(p, q, H - 1 / 3) * 255,
  );
}

export function relativeLuminanceHex(hex: string): number {
  const { r, g, b } = hexToRgb(hex);
  const f = (v: number) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}

/** 由种子色派生 MD3 风格主色与软色 */
export function deriveFromSeed(
  seed: string,
  dark: boolean,
): {
  primary: string;
  primarySoft: string;
  onPrimary: string;
  container: string;
} {
  const base = normalizeHex(seed, "#6750A4");
  const { h, s } = hexToHsl(base);
  const sat = Math.min(0.72, Math.max(0.35, s));
  if (dark) {
    const primary = hslToHex(h, sat * 0.85, 0.72);
    return {
      primary,
      primarySoft: `color-mix(in srgb, ${primary} 22%, transparent)`,
      onPrimary: "#1A1A1A",
      container: hslToHex(h, sat * 0.45, 0.22),
    };
  }
  const primary = hslToHex(h, sat, 0.42);
  return {
    primary,
    primarySoft: `color-mix(in srgb, ${primary} 14%, transparent)`,
    onPrimary: "#FFFFFF",
    container: hslToHex(h, sat * 0.35, 0.92),
  };
}

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
