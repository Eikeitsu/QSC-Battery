const QscTheme = {
  KEY: 'qsc_theme_mode',
  LABELS: {
    light: '浅色模式',
    dark: '深色模式',
    system: '跟随系统'
  },
  PRESETS: [
    { id: 'light', l: '浅色' },
    { id: 'dark', l: '深色' },
    { id: 'system', l: '跟随系统' }
  ],

  getMode() {
    try {
      return localStorage.getItem(this.KEY) || 'system';
    } catch (_) {
      return 'system';
    }
  },

  resolve(mode) {
    const value = mode || this.getMode();
    if (value === 'light' || value === 'dark') return value;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  },

  detectMonet() {
    const styles = getComputedStyle(document.documentElement);
    const bg = (styles.getPropertyValue('--background') || '').trim();
    // WebUI X 注入后 --background 一般有值；回退色与我们 :root 默认接近时也可能存在
    const hasMonet = Boolean(bg) && bg !== '';
    document.documentElement.classList.toggle('webuix-monet', hasMonet);
    return hasMonet;
  },

  readCssColor(name, fallback) {
    const raw = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    if (!raw) return fallback;
    // 可能是 #rgb / #rrggbb / rgb() / 空格分隔的 Monet 组件色
    if (raw.startsWith('#') || raw.startsWith('rgb') || raw.startsWith('hsl')) return raw;
    const parts = raw.split(/\s+/).filter(Boolean);
    if (parts.length >= 3 && parts.every((p) => /^\d+(\.\d+)?%?$/.test(p) || /^\d+(\.\d+)?$/.test(p))) {
      // "R G B" 或带 % 的相对色 → 尽量拼成 rgb
      if (parts[0].includes('%')) return `rgb(${parts[0]} ${parts[1]} ${parts[2]})`;
      return `rgb(${parts[0]}, ${parts[1]}, ${parts[2]})`;
    }
    return raw;
  },

  syncStatusBar() {
    const themeMeta = document.querySelector('meta[name="theme-color"]');
    if (!themeMeta) return;
    // 与页面实色背景一致，避免状态栏色差
    const color = this.readCssColor('--bg', this.readCssColor('--background', '#fef7ff'));
    themeMeta.setAttribute('content', color);
  },

  apply(mode) {
    const selected = mode || this.getMode();
    const resolved = this.resolve(selected);
    document.documentElement.setAttribute('data-theme', resolved);
    document.documentElement.style.colorScheme = selected === 'system' ? 'light dark' : resolved;

    this.detectMonet();
    this.syncStatusBar();

    const schemeMeta = document.querySelector('meta[name="color-scheme"]');
    if (schemeMeta) {
      schemeMeta.setAttribute('content', selected === 'system' ? 'light dark' : resolved);
    }

    const desc = document.getElementById('themeDesc');
    if (desc) {
      const label = this.LABELS[selected] || this.LABELS.system;
      const monet = document.documentElement.classList.contains('webuix-monet');
      if (selected === 'system') {
        desc.textContent = monet
          ? `${label} · 莫奈动态取色`
          : `${label}（当前${resolved === 'dark' ? '深色' : '浅色'}）`;
      } else {
        desc.textContent = monet ? `${label}（莫奈仍随系统）` : label;
      }
    }

    const chips = document.getElementById('themeChips');
    if (chips && typeof QscUi !== 'undefined') {
      QscUi.renderChips('themeChips', this.PRESETS, selected, (id) => this.setMode(id));
    }
  },

  setMode(mode) {
    const next = ['light', 'dark', 'system'].includes(mode) ? mode : 'system';
    try {
      localStorage.setItem(this.KEY, next);
    } catch (_) {}
    this.apply(next);
    if (typeof QscUi !== 'undefined') QscUi.toast(`已切换为${this.LABELS[next]}`);
  },

  init() {
    this.apply(this.getMode());
    // colors.css 可能稍晚注入，再同步一次状态栏
    requestAnimationFrame(() => this.apply(this.getMode()));
    setTimeout(() => this.syncStatusBar(), 120);
    setTimeout(() => this.syncStatusBar(), 500);

    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => {
      if (this.getMode() === 'system') this.apply('system');
      else this.syncStatusBar();
    };
    if (typeof media.addEventListener === 'function') {
      media.addEventListener('change', onChange);
    } else if (typeof media.addListener === 'function') {
      media.addListener(onChange);
    }
  }
};
