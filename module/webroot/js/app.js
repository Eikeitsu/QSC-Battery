const QscApp = {
  settings: {},
  statusTimer: null,
  bridgeReady: false,

  bindEvents() {
    document.getElementById('moduleEnabled')?.addEventListener('change', () => this.toggleModule());
    document.getElementById('temperature_switch')?.addEventListener('change', () => {
      this.save();
      QscUi.updateSubs();
    });
    ['charge_full', 'power_reset'].forEach((id) => {
      document.getElementById(id)?.addEventListener('change', () => this.save());
    });
    ['power_stop', 'power_start', 'power_stop_time', 'temperature_switch_stop', 'temperature_switch_start'].forEach((id) => {
      document.getElementById(id)?.addEventListener('change', () => {
        if (id.startsWith('power_')) this.onPowerChange();
        this.save();
      });
    });

    document.querySelector('.pref[data-toggle="module"]')?.addEventListener('click', (event) => {
      if (event.target.closest('.hyper-switch')) return;
      document.getElementById('moduleEnabled')?.click();
    });

    document.querySelectorAll('.pref[data-expand]').forEach((node) => {
      node.addEventListener('click', (event) => {
        if (event.target.closest('.hyper-switch')) return;
        if (event.target.closest('button')) return;
        QscUi.toggleExpand(node.dataset.expand);
      });
    });

    document.querySelectorAll('.pref[data-url]').forEach((node) => {
      node.addEventListener('click', () => QscApi.openUrl(node.dataset.url));
    });

    document.querySelectorAll('.pref[data-wxpay]').forEach((node) => {
      node.addEventListener('click', async () => {
        QscUi.toast('正在打开原作者投币页…');
        await QscApi.openWxPay(node.dataset.wxpay);
      });
    });

    document.querySelectorAll('.thanks-item[data-url]').forEach((node) => {
      node.addEventListener('click', () => QscApi.openUrl(node.dataset.url));
    });

    document.getElementById('refreshLogBtn')?.addEventListener('click', (event) => {
      event.stopPropagation();
      this.refreshLog(true);
    });

    document.getElementById('clearLogBtn')?.addEventListener('click', (event) => {
      event.stopPropagation();
      this.clearLog();
    });

    document.getElementById('fontSlider')?.addEventListener('input', () => QscUi.onFontSliderChange());

    window.addEventListener('resize', () => QscUi.syncTopbarSpacer());
    window.visualViewport?.addEventListener('resize', () => QscUi.syncTopbarSpacer());

    document.getElementById('resetConfigBtn')?.addEventListener('click', (event) => {
      event.stopPropagation();
      this.resetDefaults();
    });

    document.getElementById('refreshStatusBtn')?.addEventListener('click', (event) => {
      event.stopPropagation();
      this.refreshStatus(true);
    });
  },

  onPowerChange() {
    const stop = parseInt(document.getElementById('power_stop').value, 10);
    const start = parseInt(document.getElementById('power_start').value, 10);
    QscUi.renderChips('stopChips', QSC.POWER_STOP_PRESETS, Number.isNaN(stop) ? '' : String(stop), (id) => this.selectPowerStop(id));
    QscUi.renderChips('startChips', QSC.POWER_START_PRESETS, Number.isNaN(start) ? '' : String(start), (id) => this.selectPowerStart(id));
    QscUi.updateSubs();
  },

  selectPowerStop(id) {
    document.getElementById('power_stop').value = id;
    QscUi.renderChips('stopChips', QSC.POWER_STOP_PRESETS, id, (value) => this.selectPowerStop(value));
    this.onPowerChange();
    this.save();
  },

  selectPowerStart(id) {
    document.getElementById('power_start').value = id;
    QscUi.renderChips('startChips', QSC.POWER_START_PRESETS, id, (value) => this.selectPowerStart(value));
    this.onPowerChange();
    this.save();
  },

  selectTempStop(id) {
    document.getElementById('temperature_switch_stop').value = id;
    QscUi.renderChips('tempStopChips', QSC.TEMP_STOP_PRESETS, id, (value) => this.selectTempStop(value));
    QscUi.updateSubs();
    this.save();
  },

  selectTempStart(id) {
    document.getElementById('temperature_switch_start').value = id;
    QscUi.renderChips('tempStartChips', QSC.TEMP_START_PRESETS, id, (value) => this.selectTempStart(value));
    QscUi.updateSubs();
    this.save();
  },

  async toggleModule() {
    const enabled = document.getElementById('moduleEnabled').checked;
    if (enabled) {
      await QscApi.exec(`rm -f '${QSC.OFF_FLAG}'`);
      QscUi.toast('模块已开启');
    } else {
      await QscApi.exec(`touch '${QSC.OFF_FLAG}'`);
      QscUi.toast('模块已关闭');
    }
    await this.refreshStatus();
  },

  async save() {
    const powerStop = parseInt(document.getElementById('power_stop').value, 10);
    const powerStart = parseInt(document.getElementById('power_start').value, 10);
    const powerStopTime = parseInt(document.getElementById('power_stop_time').value, 10);
    const chargeFull = document.getElementById('charge_full').checked ? 1 : 0;
    const powerReset = document.getElementById('power_reset').checked ? 1 : 0;
    const tempSwitch = document.getElementById('temperature_switch').checked ? 1 : 0;
    const tempStop = parseInt(document.getElementById('temperature_switch_stop').value, 10);
    const tempStart = parseInt(document.getElementById('temperature_switch_start').value, 10);

    if (!Number.isNaN(powerStop) && !Number.isNaN(powerStart) && powerStop !== 110 && powerStop <= powerStart) {
      QscUi.toast('停止电量必须大于恢复电量');
      return;
    }
    if (tempSwitch && !Number.isNaN(tempStop) && !Number.isNaN(tempStart) && tempStop <= tempStart) {
      QscUi.toast('停止温度必须大于恢复温度');
      return;
    }

    const pairs = [
      ['power_stop', Number.isNaN(powerStop) ? 100 : powerStop],
      ['power_start', Number.isNaN(powerStart) ? 95 : powerStart],
      ['power_stop_time', Number.isNaN(powerStopTime) || powerStopTime < 1 ? 3 : powerStopTime],
      ['charge_full', chargeFull],
      ['power_reset', powerReset],
      ['temperature_switch', tempSwitch],
      ['temperature_switch_stop', Number.isNaN(tempStop) ? 60 : tempStop],
      ['temperature_switch_start', Number.isNaN(tempStart) ? 50 : tempStart]
    ];

    for (const [key, value] of pairs) {
      await QscApi.setConf(key, value);
    }

    QscUi.updateSubs();
    QscUi.toast('配置已保存');
  },

  async resetDefaults() {
    if (!window.confirm('确认恢复默认配置？')) return;

    for (const [key, value] of Object.entries(QSC.DEFAULTS)) {
      await QscApi.setConf(key, value);
      this.settings[key] = value;
    }

    this.applySettingsToForm();
    QscUi.toast('已恢复默认配置');
    await this.refreshStatus();
  },

  applySettingsToForm() {
    const s = this.settings;
    document.getElementById('power_stop').value = s.power_stop || QSC.DEFAULTS.power_stop;
    document.getElementById('power_start').value = s.power_start || QSC.DEFAULTS.power_start;
    document.getElementById('power_stop_time').value = s.power_stop_time || QSC.DEFAULTS.power_stop_time;
    document.getElementById('charge_full').checked = s.charge_full === '1';
    document.getElementById('power_reset').checked = s.power_reset === '1';
    document.getElementById('temperature_switch').checked = s.temperature_switch !== '0';
    document.getElementById('temperature_switch_stop').value = s.temperature_switch_stop || QSC.DEFAULTS.temperature_switch_stop;
    document.getElementById('temperature_switch_start').value = s.temperature_switch_start || QSC.DEFAULTS.temperature_switch_start;

    QscUi.renderChips('stopChips', QSC.POWER_STOP_PRESETS, s.power_stop || QSC.DEFAULTS.power_stop, (id) => this.selectPowerStop(id));
    QscUi.renderChips('startChips', QSC.POWER_START_PRESETS, s.power_start || QSC.DEFAULTS.power_start, (id) => this.selectPowerStart(id));
    QscUi.renderChips('tempStopChips', QSC.TEMP_STOP_PRESETS, s.temperature_switch_stop || QSC.DEFAULTS.temperature_switch_stop, (id) => this.selectTempStop(id));
    QscUi.renderChips('tempStartChips', QSC.TEMP_START_PRESETS, s.temperature_switch_start || QSC.DEFAULTS.temperature_switch_start, (id) => this.selectTempStart(id));
    QscUi.updateSubs();
  },

  async refreshStatus(showToast) {
    const badge = document.getElementById('statusBadge');

    if (!QscApi.hasBridge()) {
      document.getElementById('deviceName').textContent = '未检测到 WebUI 桥接';
      if (badge) {
        badge.className = 'status-badge disabled';
        badge.textContent = '无法执行命令，请用 KernelSU / 支持 WebUI 的管理器打开';
      }
      return;
    }

    const [capR, tempR, offR, switchR, descR, statusR, voltR, currR, verR] = await Promise.all([
      QscApi.exec(`cat /sys/class/power_supply/battery/capacity 2>/dev/null || cat /sys/class/power_supply/bms/capacity 2>/dev/null`),
      QscApi.exec(`cat /sys/class/power_supply/battery/temp 2>/dev/null || cat /sys/class/power_supply/bms/temp 2>/dev/null`),
      QscApi.exec(`[ -f '${QSC.OFF_FLAG}' ] || [ -f '${QSC.MODDIR}/disable' ] && echo 1 || echo 0`),
      QscApi.exec(`[ -f '${QSC.DATADIR}/power_switch' ] && echo 1 || echo 0`),
      QscApi.exec(`grep '^description=' '${QSC.MODDIR}/module.prop' 2>/dev/null | cut -d= -f2-`),
      QscApi.exec(`cat /sys/class/power_supply/battery/status 2>/dev/null`),
      QscApi.exec(`cat /sys/class/power_supply/battery/voltage_now 2>/dev/null`),
      QscApi.exec(`cat /sys/class/power_supply/battery/current_now 2>/dev/null`),
      QscApi.exec(`grep '^version=' '${QSC.MODDIR}/module.prop' 2>/dev/null | cut -d= -f2-`)
    ]);

    if (capR.errno === -2 || tempR.errno === -2) {
      if (badge) {
        badge.className = 'status-badge disabled';
        badge.textContent = '状态读取超时，可点刷新重试';
      }
      if (showToast) QscUi.toast('状态读取超时');
      return;
    }

    this.bridgeReady = true;
    const level = capR.stdout.trim();
    const rawTemp = parseInt(tempR.stdout.trim(), 10);
    const tempC = Number.isNaN(rawTemp) ? null : (rawTemp > 200 ? Math.round(rawTemp / 10) : rawTemp);
    const moduleOff = offR.stdout.trim() === '1';
    const chargingStopped = switchR.stdout.trim() === '1';
    const chargeStatus = statusR.stdout.trim();

    document.getElementById('statLevel').textContent = level || '--';
    document.getElementById('statTemp').textContent = tempC !== null ? tempC : '--';
    document.getElementById('moduleEnabled').checked = !moduleOff;

    if (!badge) return;
    badge.className = 'status-badge';
    const descRaw = descR.stdout.trim();
    const bracket = descRaw.match(/\[([^\]]+)\]/);
    const shortDesc = bracket ? bracket[1].trim() : '';
    const restDesc = descRaw.replace(/\[[^\]]*\]\s*/, '').trim();
    const descEl = document.getElementById('statusDesc');
    if (descEl && restDesc) descEl.textContent = restDesc;

    if (moduleOff) {
      badge.textContent = '模块已关闭';
      badge.classList.add('disabled');
    } else if (chargingStopped) {
      badge.textContent = '已停充，等待恢复';
      badge.classList.add('stopped');
    } else if (chargeStatus === 'Charging' || chargeStatus === 'Full') {
      badge.textContent = shortDesc || '充电中';
    } else {
      badge.textContent = shortDesc || '未充电';
    }

    const statusMap = {
      Charging: '充电中',
      Full: '已充满',
      Discharging: '未充电',
      'Not charging': '未充电',
      Unknown: '未知'
    };
    const chargeEl = document.getElementById('homeChargeStatus');
    if (chargeEl) {
      if (moduleOff) chargeEl.textContent = '模块关';
      else if (chargingStopped) chargeEl.textContent = '已停充';
      else chargeEl.textContent = statusMap[chargeStatus] || (chargeStatus || '--');
    }

    const voltRaw = parseInt(voltR.stdout.trim(), 10);
    const voltEl = document.getElementById('homeVoltage');
    if (voltEl) {
      voltEl.textContent = Number.isNaN(voltRaw)
        ? '--'
        : (voltRaw > 100000 ? (voltRaw / 1000000).toFixed(2) : (voltRaw / 1000).toFixed(2));
    }

    const currRaw = parseInt(currR.stdout.trim(), 10);
    const currEl = document.getElementById('homeCurrent');
    if (currEl) {
      currEl.textContent = Number.isNaN(currRaw)
        ? '--'
        : String(Math.round(Math.abs(currRaw) > 10000 ? currRaw / 1000 : currRaw));
    }

    const verEl = document.getElementById('homeVersion');
    if (verEl) verEl.textContent = verR.stdout.trim() || '--';

    const updatedEl = document.getElementById('homeUpdatedAt');
    if (updatedEl) {
      const now = new Date();
      const hh = String(now.getHours()).padStart(2, '0');
      const mm = String(now.getMinutes()).padStart(2, '0');
      const ss = String(now.getSeconds()).padStart(2, '0');
      updatedEl.textContent = `${hh}:${mm}:${ss}`;
    }

    QscUi.updateSubs();
    if (showToast) QscUi.toast('状态已刷新');
  },

  async refreshLog(showToast) {
    const lines = document.documentElement.getAttribute('data-layout') === 'dock' ? 40 : 12;
    const [logR, sizeR] = await Promise.all([
      QscApi.exec(`tail -n ${lines} '${QSC.LOG_FILE}' 2>/dev/null`),
      QscApi.exec(`wc -c < '${QSC.LOG_FILE}' 2>/dev/null`)
    ]);
    const text = logR.stdout.trim();
    const box = document.getElementById('logBox');
    if (box) box.textContent = text || '暂无日志（触发功能后才会写入）';

    const lineCount = text ? text.split('\n').filter(Boolean).length : 0;
    const lineEl = document.getElementById('logLineCount');
    if (lineEl) lineEl.textContent = String(lineCount);

    const sizeRaw = parseInt(sizeR.stdout.trim(), 10);
    const sizeEl = document.getElementById('logFileSize');
    if (sizeEl) {
      if (Number.isNaN(sizeRaw)) sizeEl.textContent = '--';
      else if (sizeRaw < 1024) sizeEl.textContent = `${sizeRaw} B`;
      else if (sizeRaw < 1024 * 1024) sizeEl.textContent = `${(sizeRaw / 1024).toFixed(1)} KB`;
      else sizeEl.textContent = `${(sizeRaw / 1024 / 1024).toFixed(2)} MB`;
    }

    const logSub = document.getElementById('logSub');
    if (logSub) logSub.textContent = lineCount ? `最近 ${lineCount} 行` : '暂无记录';

    if (!showToast) return;
    if (logR.errno === -2) QscUi.toast('日志读取超时');
    else QscUi.toast('日志已刷新');
  },

  async clearLog() {
    if (!window.confirm('确认清空日志？')) return;
    await QscApi.exec(`: > '${QSC.LOG_FILE}'`);
    await this.refreshLog(false);
    QscUi.toast('日志已清空');
  },

  async loadDeviceInfo() {
    const model = await QscApi.exec(`getprop ro.product.marketname 2>/dev/null || getprop ro.product.model 2>/dev/null`);
    const os = await QscApi.exec(`getprop ro.mi.os.version.incremental 2>/dev/null | sed 's/^OS//'`);
    const modelName = model.stdout.trim() || 'Android';
    const osName = os.stdout.trim();
    const el = document.getElementById('deviceName');
    if (!el) return;
    if (model.errno === -1 && model.stderr === 'no_ksu_bridge') {
      el.textContent = 'WebUI 桥接不可用';
      return;
    }
    el.textContent = osName ? `${modelName} · HyperOS ${osName}` : modelName;
  },

  async loadConfig() {
    for (const key of QSC.CONFIG_KEYS) {
      const value = await QscApi.getConf(key);
      this.settings[key] = value || QSC.DEFAULTS[key];
    }
    this.applySettingsToForm();
  },

  async init() {
    try {
      const savedScale = localStorage.getItem(QSC.FONT_KEY);
      if (savedScale) QscUi.applyFontScale(parseFloat(savedScale));
    } catch (_) {}

    if (typeof QscTheme !== 'undefined') QscTheme.init();

    this.bindEvents();

    // 先渲染默认值，避免一直空白；后台再拉真实数据
    this.settings = { ...QSC.DEFAULTS };
    this.applySettingsToForm();

    if (!QscApi.hasBridge()) {
      document.getElementById('deviceName').textContent = '未检测到 WebUI 桥接';
      document.getElementById('statusBadge').textContent = '请使用 KernelSU 等支持 WebUI 的管理器打开';
      document.getElementById('statusBadge').classList.add('disabled');
      QscUi.updateSubs();
      QscUi.syncTopbarSpacer();
      QscUi.toast('当前环境无法执行 shell');
      return;
    }

    await Promise.allSettled([
      this.loadDeviceInfo(),
      this.loadConfig(),
      this.refreshStatus(),
      this.refreshLog()
    ]);

    QscUi.syncTopbarSpacer();
    requestAnimationFrame(() => QscUi.syncTopbarSpacer());
    setTimeout(() => QscUi.syncTopbarSpacer(), 180);

    if (this.statusTimer) clearInterval(this.statusTimer);
    this.statusTimer = setInterval(() => this.refreshStatus(), QSC.STATUS_INTERVAL);
  }
};

document.addEventListener('DOMContentLoaded', () => {
  QscApp.init().catch((error) => {
    console.error(error);
    QscUi.toast('页面初始化失败');
  });
});
