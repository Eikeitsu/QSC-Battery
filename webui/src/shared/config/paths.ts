import { APP, STATUS_INTERVAL_MS } from "./app";

const ROOT = `/data/adb/modules/${APP.moduleId}`;

export const PATHS = {
  MODDIR: ROOT,
  CONF: `${ROOT}/config/config.conf`,
  CURRENT_CONF: `${ROOT}/config/current.json`,
  CURRENT_LIB: `${ROOT}/bin/lib/current.sh`,
  BATTERY_INFO: `${ROOT}/bin/lib/battery_info.sh`,
  DATADIR: `${ROOT}/data`,
  OFF_FLAG: `${ROOT}/data/off_qsc`,
  LOG_FILE: `${ROOT}/data/log.log`,
} as const;

export const STATUS_INTERVAL = STATUS_INTERVAL_MS;
