const QscApps = {
  entries: [],
  selected: new Set(),
  loaded: false,
  loading: false,

  parseList(raw) {
    return String(raw || "")
      .split(/\n+/)
      .map((s) => s.trim())
      .filter(Boolean);
  },

  syncFromTextarea() {
    const el = document.getElementById("app_list");
    this.selected = new Set(this.parseList(el?.value));
    this.renderSelected();
    this.renderList();
  },

  writeTextarea() {
    const el = document.getElementById("app_list");
    if (!el) return;
    // 一行一个包名，保存为 JSON 字符串数组
    el.value = [...this.selected].join("\n");
  },

  toggle(pkg, on) {
    if (on) this.selected.add(pkg);
    else this.selected.delete(pkg);
    this.writeTextarea();
    this.renderSelected();
  },

  renderSelected() {
    const box = document.getElementById("appSelectedChips");
    const count = document.getElementById("appSelectedCount");
    if (count) count.textContent = String(this.selected.size);
    if (!box) return;
    box.innerHTML = "";
    [...this.selected].forEach((pkg) => {
      const entry = this.entries.find((e) => e.package === pkg);
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = "app-chip";
      chip.textContent = entry?.name && entry.name !== pkg ? entry.name : pkg;
      chip.title = pkg;
      chip.addEventListener("click", () => {
        this.toggle(pkg, false);
        QscApp.saveCurrent?.();
      });
      box.appendChild(chip);
    });
  },

  filtered() {
    const q = (
      document.getElementById("appSearch")?.value || ""
    ).toLowerCase().trim();
    let list = this.entries;
    if (q) {
      list = list.filter(
        (e) =>
          e.package.toLowerCase().includes(q) ||
          (e.name || "").toLowerCase().includes(q),
      );
    }
    return list.slice(0, 200);
  },

  renderList() {
    const box = document.getElementById("appPickerList");
    const empty = document.getElementById("appPickerEmpty");
    if (!box) return;
    box.innerHTML = "";
    const list = this.filtered();
    if (empty) {
      empty.hidden = list.length > 0 || this.loading;
      if (!this.loaded && !this.loading) {
        empty.textContent = "点击「加载应用列表」后勾选游戏";
      } else if (this.loading) {
        empty.hidden = true;
      } else {
        empty.textContent = "无匹配应用";
      }
    }
    list.forEach((e) => {
      const row = document.createElement("label");
      row.className = "app-row";
      row.innerHTML = `
        <input type="checkbox" ${this.selected.has(e.package) ? "checked" : ""} />
        <span class="app-row-body">
          <span class="app-row-name"></span>
          <span class="app-row-pkg"></span>
        </span>`;
      row.querySelector(".app-row-name").textContent = e.name || e.package;
      row.querySelector(".app-row-pkg").textContent = e.package;
      const cb = row.querySelector("input");
      cb.addEventListener("change", () => {
        this.toggle(e.package, cb.checked);
        QscApp.saveCurrent?.();
      });
      box.appendChild(row);
    });
  },

  async load() {
    if (this.loading) return;
    this.loading = true;
    const status = document.getElementById("appPickerStatus");
    if (status) status.textContent = "正在读取已安装应用…";
    this.renderList();
    try {
      this.entries = await QscApi.listInstalledApps();
      this.loaded = true;
      if (status) {
        status.textContent = `已加载 ${this.entries.length} 个用户应用（可搜索名称或包名）`;
      }
    } catch (error) {
      this.entries = [];
      if (status) status.textContent = "读取失败，请重试或手动编辑包名";
    }
    this.loading = false;
    this.syncFromTextarea();
  },

  bind() {
    document
      .getElementById("appLoadBtn")
      ?.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        this.load();
      });
    document.getElementById("appSearch")?.addEventListener("input", () => {
      this.renderList();
    });
    document.getElementById("app_list")?.addEventListener("change", () => {
      this.syncFromTextarea();
    });
  },
};
