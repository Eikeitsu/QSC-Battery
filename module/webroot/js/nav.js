const QscNav = {
  PAGE_KEY: 'qsc_dock_page',
  PAGES: [
    {
      id: 'home',
      label: '概览',
      icon: `<svg class="dock-svg" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 3.6 4 10.4V20a1 1 0 0 0 1 1h5v-6h4v6h5a1 1 0 0 0 1-1v-9.6L12 3.6Zm0-2.1c.4 0 .8.1 1.1.4l8 6.8c.5.4.7 1 .7 1.7V20a3 3 0 0 1-3 3h-5a1 1 0 0 1-1-1v-6h-2v6a1 1 0 0 1-1 1H5a3 3 0 0 1-3-3v-9.6c0-.7.3-1.3.7-1.7l8-6.8c.3-.3.7-.4 1.1-.4Z"/></svg>`
    },
    {
      id: 'config',
      label: '配置',
      icon: `<svg class="dock-svg" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M4 7.25h7.1a2.75 2.75 0 0 0 5.3 0H20a1 1 0 1 0 0-2h-3.6a2.75 2.75 0 0 0-5.3 0H4a1 1 0 1 0 0 2Zm9.75-1.75a.75.75 0 1 1 0 1.5.75.75 0 0 1 0-1.5ZM4 13.25h2.1a2.75 2.75 0 0 0 5.3 0H20a1 1 0 1 0 0-2H11.4a2.75 2.75 0 0 0-5.3 0H4a1 1 0 1 0 0 2Zm4.75-1.75a.75.75 0 1 1 0 1.5.75.75 0 0 1 0-1.5ZM4 19.25h9.1a2.75 2.75 0 0 0 5.3 0H20a1 1 0 1 0 0-2h-1.6a2.75 2.75 0 0 0-5.3 0H4a1 1 0 1 0 0 2Zm11.75-1.75a.75.75 0 1 1 0 1.5.75.75 0 0 1 0-1.5Z"/></svg>`
    },
    {
      id: 'log',
      label: '日志',
      icon: `<svg class="dock-svg" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M7 2.75h10A2.25 2.25 0 0 1 19.25 5v14A2.25 2.25 0 0 1 17 21.25H7A2.25 2.25 0 0 1 4.75 19V5A2.25 2.25 0 0 1 7 2.75Zm0 1.5c-.41 0-.75.34-.75.75v14c0 .41.34.75.75.75h10c.41 0 .75-.34.75-.75V5c0-.41-.34-.75-.75-.75H7Zm1.5 3.5h7a.75.75 0 0 1 0 1.5h-7a.75.75 0 0 1 0-1.5Zm0 4h7a.75.75 0 0 1 0 1.5h-7a.75.75 0 0 1 0-1.5Zm0 4h4.5a.75.75 0 0 1 0 1.5H8.5a.75.75 0 0 1 0-1.5Z"/></svg>`
    },
    {
      id: 'more',
      label: '更多',
      icon: `<svg class="dock-svg" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M6 10.25a1.75 1.75 0 1 1 0 3.5 1.75 1.75 0 0 1 0-3.5Zm6 0a1.75 1.75 0 1 1 0 3.5 1.75 1.75 0 0 1 0-3.5Zm6 0a1.75 1.75 0 1 1 0 3.5 1.75 1.75 0 0 1 0-3.5Z"/></svg>`
    }
  ],
  LEGACY: {
    power: 'config',
    temp: 'config',
    extra: 'config',
    guide: 'more',
    about: 'more'
  },

  getPage() {
    try {
      let id = localStorage.getItem(this.PAGE_KEY) || 'home';
      if (this.LEGACY[id]) id = this.LEGACY[id];
      return this.PAGES.some((p) => p.id === id) ? id : 'home';
    } catch (_) {
      return 'home';
    }
  },

  setPage(id) {
    if (this.LEGACY[id]) id = this.LEGACY[id];
    const page = this.PAGES.some((p) => p.id === id) ? id : 'home';
    try {
      localStorage.setItem(this.PAGE_KEY, page);
    } catch (_) {}
    document.documentElement.setAttribute('data-page', page);
    document.querySelectorAll('.dock-item').forEach((el) => {
      el.classList.toggle('active', el.dataset.page === page);
    });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  },

  renderDock() {
    const nav = document.getElementById('dockNav');
    if (!nav) return;
    const current = this.getPage();
    nav.innerHTML = this.PAGES.map((p) => `
      <button type="button" class="dock-item${p.id === current ? ' active' : ''}" data-page="${p.id}" aria-label="${p.label}">
        <span class="dock-icon">${p.icon}</span>
        <span class="dock-label">${p.label}</span>
      </button>
    `).join('');
    nav.querySelectorAll('.dock-item').forEach((btn) => {
      btn.addEventListener('click', () => this.setPage(btn.dataset.page));
    });
  },

  apply(layout) {
    const dock = layout === 'dock';
    const nav = document.getElementById('dockNav');
    if (nav) nav.hidden = !dock;
    if (dock) {
      this.renderDock();
      this.setPage(this.getPage());
    } else {
      document.documentElement.removeAttribute('data-page');
    }
  }
};
