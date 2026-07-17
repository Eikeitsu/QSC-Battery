const QscTheme = {
  KEY: 'qsc_theme_mode',
  MONET_KEY: 'qsc_monet',
  LAYOUT_KEY: 'qsc_layout',
  COMPACT_KEY: 'qsc_compact',
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

  getMonet() {
    try {
      const v = localStorage.getItem(this.MONET_KEY);
      return v === null ? true : v === '1';
    } catch (_) {
      return true;
    }
  },

  getLayout() {
    try {
      return localStorage.getItem(this.LAYOUT_KEY) || 'classic';
    } catch (_) {
      return 'classic';
    }
  },

  getCompact() {
    try {
      return localStorage.getItem(this.COMPACT_KEY) === '1';
    } catch (_) {
      return false;
    }
  },

  resolve(mode) {
    const value = mode || this.getMode();
    if (value === 'light' || value === 'dark') return value;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  },

  readCssColor(name, fallback) {
    const raw = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    if (!raw) return fallback;
    if (raw.startsWith('#') || raw.startsWith('rgb') || raw.startsWith('hsl')) return raw;
    const parts = raw.split(/\s+/).filter(Boolean);
    if (parts.length >= 3) {
      if (parts[0].includes('%')) return `rgb(${parts[0]} ${parts[1]} ${parts[2]})`;
      return `rgb(${parts[0]}, ${parts[1]}, ${parts[2]})`;
    }
    return raw;
  },

  syncStatusBar() {
    const themeMeta = document.querySelector('meta[name="theme-color"]');
    if (!themeMeta) return;
    const monet = this.getMonet();
    const color = monet
      ? this.readCssColor('--background', this.readCssColor('--bg', '#f2f4f7'))
      : this.readCssColor('--bg', '#f2f4f7');
    themeMeta.setAttribute('content', color);
    document.documentElement.style.backgroundColor = color;
    if (document.body) document.body.style.backgroundColor = color;
  },

  applyMonet(enabled) {
    const on = enabled !== false && enabled !== '0';
    document.documentElement.classList.toggle('monet-on', on);
    document.documentElement.classList.toggle('monet-off', !on);
    const sw = document.getElementById('monetEnabled');
    if (sw) sw.checked = on;
    const desc = document.getElementById('monetDesc');
    if (desc) desc.textContent = on ? '全局跟随系统莫奈取色' : '使用固定暖橙配色';

  },

  setMonet(on) {
    try {
      localStorage.setItem(this.MONET_KEY, on ? '1' : '0');
    } catch (_) {}
    this.applyMonet(on);
    this.syncStatusBar();
    if (typeof QscUi !== 'undefined') QscUi.toast(on ? '已开启莫奈取色' : '已关闭莫奈取色');
  },

  applyLayout(layout) {
    const mode = layout === 'dock' ? 'dock' : 'classic';
    document.documentElement.setAttribute('data-layout', mode);
    const sw = document.getElementById('dockEnabled');
    if (sw) sw.checked = mode === 'dock';
    const desc = document.getElementById('dockDesc');
    if (desc) desc.textContent = mode === 'dock' ? '底部悬浮分页导航' : '单页长列表';
    if (typeof QscNav !== 'undefined') QscNav.apply(mode);
  },

  setLayout(layout) {
    const mode = layout === 'dock' ? 'dock' : 'classic';
    try {
      localStorage.setItem(this.LAYOUT_KEY, mode);
    } catch (_) {}
    this.applyLayout(mode);
    if (typeof QscUi !== 'undefined') {
      QscUi.toast(mode === 'dock' ? '已开启悬浮分页' : '已切换为经典单页');
    }
  },

  applyCompact(enabled) {
    const on = enabled === true || enabled === '1';
    document.documentElement.classList.toggle('compact-on', on);
    document.documentElement.classList.toggle('compact-off', !on);
    const sw = document.getElementById('compactEnabled');
    if (sw) sw.checked = on;
    const desc = document.getElementById('compactDesc');
    if (desc) desc.textContent = on ? '卡片与列表间距更紧凑' : '舒展间距，便于阅读';
  },

  setCompact(on) {
    try {
      localStorage.setItem(this.COMPACT_KEY, on ? '1' : '0');
    } catch (_) {}
    this.applyCompact(on);
    if (typeof QscUi !== 'undefined') {
      QscUi.toast(on ? '已开启卡片紧凑' : '已关闭卡片紧凑');
    }
  },

  apply(mode) {
    const selected = mode || this.getMode();
    const resolved = this.resolve(selected);
    document.documentElement.setAttribute('data-theme', resolved);
    document.documentElement.style.colorScheme = selected === 'system' ? 'light dark' : resolved;

    this.applyMonet(this.getMonet());
    this.applyLayout(this.getLayout());
    this.applyCompact(this.getCompact());
    this.syncStatusBar();
    if (typeof QscUi !== 'undefined') QscUi.syncTopbarSpacer();

    const schemeMeta = document.querySelector('meta[name="color-scheme"]');
    if (schemeMeta) {
      schemeMeta.setAttribute('content', selected === 'system' ? 'light dark' : resolved);
    }

    const desc = document.getElementById('themeDesc');
    if (desc) {
      const label = this.LABELS[selected] || this.LABELS.system;
      desc.textContent = selected === 'system'
        ? `${label}（当前${resolved === 'dark' ? '深色' : '浅色'}）`
        : label;
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
    requestAnimationFrame(() => this.syncStatusBar());
    setTimeout(() => this.syncStatusBar(), 120);
    setTimeout(() => this.syncStatusBar(), 500);

    document.getElementById('monetEnabled')?.addEventListener('change', (e) => {
      this.setMonet(e.target.checked);
    });
    document.getElementById('dockEnabled')?.addEventListener('change', (e) => {
      this.setLayout(e.target.checked ? 'dock' : 'classic');
    });
    document.getElementById('compactEnabled')?.addEventListener('change', (e) => {
      this.setCompact(e.target.checked);
    });

    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => {
      if (this.getMode() === 'system') this.apply('system');
      else this.syncStatusBar();
    };
    if (typeof media.addEventListener === 'function') media.addEventListener('change', onChange);
    else if (typeof media.addListener === 'function') media.addListener(onChange);
  }
};
