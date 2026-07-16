const QSC = {
  MODDIR: '/data/adb/modules/QuantitativeStopCharging_switch',
  CONF: '/data/adb/modules/QuantitativeStopCharging_switch/config/config.conf',
  DATADIR: '/data/adb/modules/QuantitativeStopCharging_switch/data',
  ASSETDIR: '/data/adb/modules/QuantitativeStopCharging_switch/assets',
  OFF_FLAG: '/data/adb/modules/QuantitativeStopCharging_switch/data/off_qsc',
  LOG_FILE: '/data/adb/modules/QuantitativeStopCharging_switch/data/log.log',
  FONT_KEY: 'qsc_font_scale',
  STATUS_INTERVAL: 5000,
  POWER_STOP_PRESETS: [
    { id: '80', l: '80%' }, { id: '85', l: '85%' }, { id: '90', l: '90%' },
    { id: '95', l: '95%' }, { id: '100', l: '100%' }, { id: '110', l: '关闭' }
  ],
  POWER_START_PRESETS: [
    { id: '75', l: '75%' }, { id: '80', l: '80%' }, { id: '85', l: '85%' },
    { id: '90', l: '90%' }, { id: '95', l: '95%' }
  ],
  TEMP_STOP_PRESETS: [
    { id: '50', l: '50°C' }, { id: '55', l: '55°C' },
    { id: '60', l: '60°C' }, { id: '65', l: '65°C' }
  ],
  TEMP_START_PRESETS: [
    { id: '40', l: '40°C' }, { id: '45', l: '45°C' },
    { id: '50', l: '50°C' }, { id: '55', l: '55°C' }
  ],
  CONFIG_KEYS: [
    'power_stop', 'power_start', 'power_stop_time', 'charge_full', 'power_reset',
    'temperature_switch', 'temperature_switch_stop', 'temperature_switch_start'
  ]
};
