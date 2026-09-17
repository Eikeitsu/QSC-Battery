import { APP, STATUS_INTERVAL_MS } from "./app";

const ROOT = `/data/adb/modules/${APP.moduleId}`;

export const PATHS = {
  MODDIR: ROOT,
  CONF: `${ROOT}/config/config.conf`,
  CURRENT_CONF: `${ROOT}/config/current.json`,
  PROFILES: `${ROOT}/config/profiles.json`,
  CURRENT_LIB: `${ROOT}/bin/lib/current.sh`,
  BATTERY_INFO: `${ROOT}/bin/lib/battery_info.sh`,
  TEST_SWITCH: `${ROOT}/bin/test_switch.sh`,
  TEST_SWITCH_BG: `${ROOT}/bin/test_switch_bg.sh`,
  DATADIR: `${ROOT}/data`,
  OFF_FLAG: `${ROOT}/data/off_qsc`,
  LOG_FILE: `${ROOT}/data/log.log`,
  LIST_SWITCH: `${ROOT}/data/list_switch`,
  DEVICE_PROFILE: `${ROOT}/data/device.profile`,
  STOP_FAIL_HINT: `${ROOT}/data/stop_fail_hint`,
  NO_NODE_LOGGED: `${ROOT}/data/no_node_logged`,
  SWITCH_TEST_STATUS: `${ROOT}/data/switch_test_status`,
  CHARGE_HISTORY: `${ROOT}/data/charge_history.csv`,
  CHARGE_EVENTS: `${ROOT}/data/charge_events.log`,
  HEALTH_HISTORY: `${ROOT}/data/health_history.csv`,
  COMPAT_HINT: `${ROOT}/data/compat_hint`,
  PROFILES_DIR: `${ROOT}/data/profiles`,
  QSCD: `${ROOT}/bin/qscd`,
  QSCD_FETCH: `${ROOT}/bin/qscd_fetch.sh`,
  QSCD_PROGRESS: `${ROOT}/data/qscd_download_progress`,
} as const;

export const STATUS_INTERVAL = STATUS_INTERVAL_MS;
