const QscTheme = {
  KEY: "qsc_theme_mode",
  MONET_KEY: "qsc_monet",
  LAYOUT_KEY: "qsc_layout",
  COMPACT_KEY: "qsc_compact",
  LABELS: {
    light: "浅色模式",
    dark: "深色模式",
    system: "跟随系统",
  },
  PRESETS: [
    { id: "light", l: "浅色" },
    { id: "dark", l: "深色" },
    { id: "system", l: "跟随系统" },
  ],

  getMode() {
    try {
      return localStorage.getItem(this.KEY) || "system";
    } catch (_) {
      return "system";
    }
  },

  getMonet() {
    try {
      const v = localStorage.getItem(this.MONET_KEY);
      return v === null ? true : v === "1";
    } catch (_) {
      return true;
    }
  },

  getLayout() {
    try {
      return localStorage.getItem(this.LAYOUT_KEY) || "classic";
    } catch (_) {
      return "classic";
    }
  },

  getCompact() {
    try {
      return localStorage.getItem(this.COMPACT_KEY) === "1";
    } catch (_) {
      return false;
    }
  },

  resolve(mode) {
    const value = mode || this.getMode();
    if (value === "light" || value === "dark") return value;
    return window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  },

  readCssColor(name, fallback) {
    const raw = getComputedStyle(document.documentElement)
      .getPropertyValue(name)
      .trim();
    if (!raw) return fallback;
    if (raw.startsWith("#") || raw.startsWith("rgb") || raw.startsWith("hsl"))
      return raw;
    const parts = raw.split(/\s+/).filter(Boolean);
    if (parts.length >= 3) {
      if (parts[0].includes("%"))
        return `rgb(${parts[0]} ${parts[1]} ${parts[2]})`;
      return `rgb(${parts[0]}, ${parts[1]}, ${parts[2]})`;
    }
    return raw;
  },

  relativeLuminance(color) {
    const m = String(color || "")
      .trim()
      .match(/rgba?\(\s*([\d.]+)\s*,?\s*([\d.]+)\s*,?\s*([\d.]+)/i);
    let r;
    let g;
    let b;
    if (m) {
      r = Number(m[1]);
      g = Number(m[2]);
      b = Number(m[3]);
      if (r <= 1 && g <= 1 && b <= 1) {
        r *= 255;
        g *= 255;
        b *= 255;
      }
    } else if (color.startsWith("#")) {
      let hex = color.slice(1);
      if (hex.length === 3)
        hex = hex
          .split("")
          .map((c) => c + c)
          .join("");
      if (hex.length !== 6) return 1;
      r = parseInt(hex.slice(0, 2), 16);
      g = parseInt(hex.slice(2, 4), 16);
      b = parseInt(hex.slice(4, 6), 16);
    } else {
      return 1;
    }
    const toLin = (v) => {
      const s = v / 255;
      return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * toLin(r) + 0.7152 * toLin(g) + 0.0722 * toLin(b);
  },

  /**
   * MMRL / WebUI-X：setLightStatusBars(true)=深色图标；false=浅色（白）图标。
   * 仅改 color-scheme / theme-color 对原生状态栏不够。
   */
  applySystemBarIcons(barDark) {
    const lightBars = !barDark;
    const trySet = (api) => {
      if (!api || typeof api !== "object") return false;
      let ok = false;
      try {
        if (typeof api.setLightStatusBars === "function") {
          api.setLightStatusBars(lightBars);
          ok = true;
        }
        if (typeof api.setLightNavigationBars === "function") {
          api.setLightNavigationBars(lightBars);
          ok = true;
        }
      } catch (_) {}
      return ok;
    };
    if (trySet(window.$QSC_Battery)) return;
    if (trySet(window.mmrl)) return;
    if (trySet(window.ksu)) return;
    try {
      Object.keys(window).forEach((k) => {
        if (!k || k.charAt(0) !== "$") return;
        trySet(window[k]);
      });
    } catch (_) {}
  },

  syncStatusBar() {
    const themeMeta = document.querySelector('meta[name="theme-color"]');
    if (!themeMeta) return;
    const resolved = this.resolve(this.getMode());
    const monet = this.getMonet();
    // 普通深色与莫奈深色底色不同，勿共用同一回退
    const fallback =
      resolved === "dark"
        ? monet
          ? "#16141c"
          : "#111317"
        : monet
          ? "#fef7ff"
          : "#f2f4f7";
    let color = this.readCssColor("--bg", fallback);
    // 深色下若仍读到过亮底（token 未跟上），强制回退
    if (resolved === "dark" && this.relativeLuminance(color) > 0.42) {
      color = fallback;
    }
    if (resolved === "light" && this.relativeLuminance(color) < 0.2) {
      color = fallback;
    }
    themeMeta.setAttribute("content", color);
    document.documentElement.style.backgroundColor = color;
    if (document.body) document.body.style.backgroundColor = color;

    // 时钟/电量等系统图标反色：跟最终状态栏底色亮度走，而不是只改页面背景
    // 深底 → only dark（浅色图标）；浅底 → only light（深色图标）
    const barDark = this.relativeLuminance(color) < 0.45;
    const scheme = barDark ? "only dark" : "only light";
    document.documentElement.style.colorScheme = scheme;
    const schemeMeta = document.querySelector('meta[name="color-scheme"]');
    if (schemeMeta) schemeMeta.setAttribute("content", scheme);
    this.applySystemBarIcons(barDark);

    this.ensureTextContrast(resolved);
  },

  // 深色底必须配浅色字；管理器 MD3 token 极性错乱时仅改背景会黑字黑底
  ensureTextContrast(resolved) {
    const root = document.documentElement;
    const props = ["--fg", "--text", "--text-2", "--text-3"];
    const clear = () => props.forEach((p) => root.style.removeProperty(p));
    const mode = resolved || this.resolve(this.getMode());

    if (mode === "dark") {
      const text = this.readCssColor("--text", "#f2f3f5");
      const fg = this.readCssColor("--fg", text);
      if (
        this.relativeLuminance(text) < 0.42 ||
        this.relativeLuminance(fg) < 0.42
      ) {
        root.style.setProperty("--fg", "#f2f3f5");
        root.style.setProperty("--text", "#f2f3f5");
        root.style.setProperty("--text-2", "#a8a8b0");
        root.style.setProperty("--text-3", "#8e8e96");
        if (document.body) document.body.style.color = "#f2f3f5";
      } else {
        clear();
        if (document.body) document.body.style.removeProperty("color");
      }
      return;
    }

    const text = this.readCssColor("--text", "#1c1c1e");
    const fg = this.readCssColor("--fg", text);
    if (
      this.relativeLuminance(text) > 0.55 ||
      this.relativeLuminance(fg) > 0.55
    ) {
      root.style.setProperty("--fg", "#1c1c1e");
      root.style.setProperty("--text", "#1c1c1e");
      root.style.setProperty("--text-2", "#6c6c70");
      root.style.setProperty("--text-3", "#8e8e93");
      if (document.body) document.body.style.color = "#1c1c1e";
    } else {
      clear();
      if (document.body) document.body.style.removeProperty("color");
    }
  },

  applyMonet(enabled) {
    const on = enabled !== false && enabled !== "0";
    document.documentElement.classList.toggle("monet-on", on);
    document.documentElement.classList.toggle("monet-off", !on);
    const sw = document.getElementById("monetEnabled");
    if (sw) sw.checked = on;
    const desc = document.getElementById("monetDesc");
    if (desc)
      desc.textContent = on
        ? "浅色/深色均跟随系统莫奈色相"
        : "使用固定暖橙配色";
  },

  setMonet(on) {
    try {
      localStorage.setItem(this.MONET_KEY, on ? "1" : "0");
    } catch (_) {}
    this.applyMonet(on);
    // 莫奈开关后需按当前深浅色重新套用，避免停在浅色表面
    this.apply(this.getMode());
    if (typeof QscUi !== "undefined")
      QscUi.toast(on ? "已开启莫奈取色" : "已关闭莫奈取色");
  },

  applyLayout(layout) {
    const mode = layout === "dock" ? "dock" : "classic";
    document.documentElement.setAttribute("data-layout", mode);
    const sw = document.getElementById("dockEnabled");
    if (sw) sw.checked = mode === "dock";
    const desc = document.getElementById("dockDesc");
    if (desc)
      desc.textContent = mode === "dock" ? "底部悬浮分页导航" : "单页长列表";
    if (typeof QscNav !== "undefined") QscNav.apply(mode);
  },

  setLayout(layout) {
    const mode = layout === "dock" ? "dock" : "classic";
    try {
      localStorage.setItem(this.LAYOUT_KEY, mode);
    } catch (_) {}
    this.applyLayout(mode);
    if (typeof QscUi !== "undefined") {
      QscUi.toast(mode === "dock" ? "已开启悬浮分页" : "已切换为经典单页");
    }
  },

  applyCompact(enabled) {
    const on = enabled === true || enabled === "1";
    document.documentElement.classList.toggle("compact-on", on);
    document.documentElement.classList.toggle("compact-off", !on);
    const sw = document.getElementById("compactEnabled");
    if (sw) sw.checked = on;
    const desc = document.getElementById("compactDesc");
    if (desc)
      desc.textContent = on ? "卡片与列表间距更紧凑" : "舒展间距，便于阅读";
  },

  setCompact(on) {
    try {
      localStorage.setItem(this.COMPACT_KEY, on ? "1" : "0");
    } catch (_) {}
    this.applyCompact(on);
    if (typeof QscUi !== "undefined") {
      QscUi.toast(on ? "已开启卡片紧凑" : "已关闭卡片紧凑");
    }
  },

  syncBrandMarks(resolved) {
    const dark = (resolved || this.resolve(this.getMode())) === "dark";
    document.querySelectorAll(".about-brand-mark").forEach((img) => {
      const next = dark
        ? img.getAttribute("data-mark-dark")
        : img.getAttribute("data-mark-light");
      if (next && img.getAttribute("src") !== next) img.setAttribute("src", next);
    });
  },

  apply(mode) {
    const selected = mode || this.getMode();
    const resolved = this.resolve(selected);
    // 先切 color-scheme，便于管理器 colors.css 注入对应深浅 token
    document.documentElement.style.colorScheme =
      resolved === "dark" ? "only dark" : "only light";
    document.documentElement.setAttribute("data-theme", resolved);

    this.applyMonet(this.getMonet());
    this.applyLayout(this.getLayout());
    this.applyCompact(this.getCompact());
    this.syncBrandMarks(resolved);
    // syncStatusBar 会按最终底色亮度再校准 theme-color 与 only dark/light（状态栏图标反色）
    this.syncStatusBar();
    if (typeof QscUi !== "undefined") QscUi.syncTopbarSpacer();

    const desc = document.getElementById("themeDesc");
    if (desc) {
      const label = this.LABELS[selected] || this.LABELS.system;
      desc.textContent =
        selected === "system"
          ? `${label}（当前${resolved === "dark" ? "深色" : "浅色"}）`
          : label;
    }

    const chips = document.getElementById("themeChips");
    if (chips && typeof QscUi !== "undefined") {
      QscUi.renderChips("themeChips", this.PRESETS, selected, (id) =>
        this.setMode(id),
      );
    }

    // colors.css 异步生效时再校准一次状态栏
    requestAnimationFrame(() => this.syncStatusBar());
  },

  setMode(mode) {
    const next = ["light", "dark", "system"].includes(mode) ? mode : "system";
    try {
      localStorage.setItem(this.KEY, next);
    } catch (_) {}
    this.apply(next);
    if (typeof QscUi !== "undefined")
      QscUi.toast(`已切换为${this.LABELS[next]}`);
  },

  init() {
    this.apply(this.getMode());
    requestAnimationFrame(() => this.syncStatusBar());
    setTimeout(() => this.syncStatusBar(), 120);
    setTimeout(() => this.syncStatusBar(), 500);

    document.getElementById("monetEnabled")?.addEventListener("change", (e) => {
      this.setMonet(e.target.checked);
    });
    document.getElementById("dockEnabled")?.addEventListener("change", (e) => {
      this.setLayout(e.target.checked ? "dock" : "classic");
    });
    document
      .getElementById("compactEnabled")
      ?.addEventListener("change", (e) => {
        this.setCompact(e.target.checked);
      });

    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => {
      if (this.getMode() === "system") this.apply("system");
      else this.syncStatusBar();
    };
    if (typeof media.addEventListener === "function")
      media.addEventListener("change", onChange);
    else if (typeof media.addListener === "function")
      media.addListener(onChange);
  },
};
