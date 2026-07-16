const QscApp = {
  settings: {},
  statusTimer: null,

  bindEvents() {
    document.getElementById('moduleEnabled').addEventListener('change', () => this.toggleModule());
    document.getElementById('temperature_switch').addEventListener('change', () => {
      this.save();
      QscUi.updateSubs();
    });
    ['charge_full', 'power_reset'].forEach((id) => {
      document.getElementById(id).addEventListener('change', () => this.save());
    });
    ['power_stop', 'power_start', 'power_stop_time', 'temperature_switch_stop', 'temperature_switch_start'].forEach((id) => {
      document.getElementById(id).addEventListener('change', () => {
        if (id.startsWith('power_')) this.onPowerChange();
        this.save();
      });
    });
    document.querySelector('.pref[data-toggle="module"]')?.addEventListener('click', () => {
      document.getElementById('moduleEnabled').click();
    });
    document.querySelectorAll('.pref[data-expand]').forEach((node) => {
      node.addEventListener('click', () => QscUi.toggleExpand(node.dataset.expand));
    });
    document.querySelectorAll('.pref[data-url]').forEach((node) => {
      node.addEventListener('click', () => QscApi.openUrl(node.dataset.url));
    });
    document.querySelectorAll('.thanks-item[data-url]').forEach((node) => {
      node.addEventListener('click', () => QscApi.openUrl(node.dataset.url));
    });
    document.getElementById('refreshLogBtn')?.addEventListener('click', (event) => {
      event.stopPropagation();
      this.refreshLog();
    });
    document.getElementById('fontSlider')?.addEventListener('input', () => QscUi.onFontSliderChange());
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
    this.save();
  },

  selectTempStart(id) {
    document.getElementById('temperature_switch_start').value = id;
    QscUi.renderChips('tempStartChips', QSC.TEMP_START_PRESETS, id, (value) => this.selectTempStart(value));
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
    QscUi.toast('配置已保存，即时生效');
  },

  async refreshStatus() {
    const [capR, tempR, offR, switchR, descR, statusR] = await Promise.all([
      QscApi.exec(`cat /sys/class/power_supply/battery/capacity 2>/dev/null || cat /sys/class/power_supply/bms/capacity 2>/dev/null`),
      QscApi.exec(`cat /sys/class/power_supply/battery/temp 2>/dev/null || cat /sys/class/power_supply/bms/temp 2>/dev/null`),
      QscApi.exec(`[ -f '${QSC.OFF_FLAG}' ] || [ -f '${QSC.MODDIR}/disable' ] && echo 1 || echo 0`),
      QscApi.exec(`[ -f '${QSC.DATADIR}/power_switch' ] && echo 1 || echo 0`),
      QscApi.exec(`grep '^description=' '${QSC.MODDIR}/module.prop' 2>/dev/null | cut -d= -f2-`),
      QscApi.exec(`cat /sys/class/power_supply/battery/status 2>/dev/null`)
    ]);

    const level = capR.stdout.trim();
    const rawTemp = parseInt(tempR.stdout.trim(), 10);
    const tempC = Number.isNaN(rawTemp) ? null : (rawTemp > 200 ? Math.round(rawTemp / 10) : rawTemp);
    const moduleOff = offR.stdout.trim() === '1';
    const chargingStopped = switchR.stdout.trim() === '1';
    const chargeStatus = statusR.stdout.trim();

    document.getElementById('statLevel').textContent = level || '--';
    document.getElementById('statTemp').textContent = tempC !== null ? tempC : '--';
    document.getElementById('moduleEnabled').checked = !moduleOff;

    const badge = document.getElementById('statusBadge');
    badge.className = 'status-badge';
    if (moduleOff) {
      badge.textContent = '模块已关闭';
      badge.classList.add('disabled');
    } else if (chargingStopped) {
      badge.textContent = '已触发停充，等待恢复条件';
      badge.classList.add('stopped');
    } else if (chargeStatus === 'Charging' || chargeStatus === 'Full') {
      badge.textContent = descR.stdout.trim() || '[ 充电中 ]';
    } else {
      badge.textContent = descR.stdout.trim() || '[ 未充电 ]';
    }
  },

  async refreshLog() {
    const result = await QscApi.exec(`tail -n 12 '${QSC.LOG_FILE}' 2>/dev/null`);
    const text = result.stdout.trim();
    document.getElementById('logBox').textContent = text || '暂无日志（触发功能后才会写入）';
  },

  async loadBackground() {
    const paths = [
      `'${QSC.ASSETDIR}/donate.jpg'`,
      `'${QSC.ASSETDIR}/pay.jpg'`,
      `'${QSC.MODDIR}/pay.jpg'`
    ];
    for (const path of paths) {
      const result = await QscApi.exec(`base64 -w0 ${path} 2>/dev/null`);
      if (result.stdout.trim()) {
        document.getElementById('bgImage').style.backgroundImage = `url('data:image/jpeg;base64,${result.stdout.trim()}')`;
        return;
      }
    }
    document.getElementById('bgImage').style.background = 'radial-gradient(circle at 30% 40%, #fff5e6 0%, #f5e6d3 100%)';
  },

  async loadDeviceInfo() {
    const model = await QscApi.exec(`getprop ro.product.marketname 2>/dev/null || getprop ro.product.model 2>/dev/null`);
    const os = await QscApi.exec(`getprop ro.mi.os.version.incremental 2>/dev/null | sed 's/^OS//'`);
    const modelName = model.stdout.trim() || 'Android';
    const osName = os.stdout.trim();
    document.getElementById('deviceName').textContent = osName
      ? `${modelName} · HyperOS ${osName}`
      : modelName;
  },

  async loadConfig() {
    for (const key of QSC.CONFIG_KEYS) {
      this.settings[key] = await QscApi.getConf(key);
    }

    document.getElementById('power_stop').value = this.settings.power_stop || '100';
    document.getElementById('power_start').value = this.settings.power_start || '95';
    document.getElementById('power_stop_time').value = this.settings.power_stop_time || '3';
    document.getElementById('charge_full').checked = this.settings.charge_full === '1';
    document.getElementById('power_reset').checked = this.settings.power_reset === '1';
    document.getElementById('temperature_switch').checked = this.settings.temperature_switch !== '0';
    document.getElementById('temperature_switch_stop').value = this.settings.temperature_switch_stop || '60';
    document.getElementById('temperature_switch_start').value = this.settings.temperature_switch_start || '50';

    QscUi.renderChips('stopChips', QSC.POWER_STOP_PRESETS, this.settings.power_stop || '100', (id) => this.selectPowerStop(id));
    QscUi.renderChips('startChips', QSC.POWER_START_PRESETS, this.settings.power_start || '95', (id) => this.selectPowerStart(id));
    QscUi.renderChips('tempStopChips', QSC.TEMP_STOP_PRESETS, this.settings.temperature_switch_stop || '60', (id) => this.selectTempStop(id));
    QscUi.renderChips('tempStartChips', QSC.TEMP_START_PRESETS, this.settings.temperature_switch_start || '50', (id) => this.selectTempStart(id));
    QscUi.updateSubs();
  },

  async init() {
    try {
      const savedScale = localStorage.getItem(QSC.FONT_KEY);
      if (savedScale) QscUi.applyFontScale(parseFloat(savedScale));
    } catch (_) {}

    this.bindEvents();
    await this.loadBackground();
    await this.loadDeviceInfo();
    await this.loadConfig();
    await this.refreshStatus();
    await this.refreshLog();

    if (this.statusTimer) clearInterval(this.statusTimer);
    this.statusTimer = setInterval(() => this.refreshStatus(), QSC.STATUS_INTERVAL);
  }
};

document.addEventListener('DOMContentLoaded', () => QscApp.init());
