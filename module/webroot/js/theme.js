const QscTheme = {
  KEY: 'qsc_theme_mode',
  COLORS: {
    light: '#f2f4f7',
    dark: '#0f1115'
  },
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

  apply(mode) {
    const selected = mode || this.getMode();
    const resolved = this.resolve(selected);
    document.documentElement.setAttribute('data-theme', resolved);
    document.documentElement.style.colorScheme = resolved;

    const themeMeta = document.querySelector('meta[name="theme-color"]');
    if (themeMeta) themeMeta.setAttribute('content', this.COLORS[resolved]);

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
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => {
      if (this.getMode() === 'system') this.apply('system');
    };
    if (typeof media.addEventListener === 'function') {
      media.addEventListener('change', onChange);
    } else if (typeof media.addListener === 'function') {
      media.addListener(onChange);
    }
  }
};
