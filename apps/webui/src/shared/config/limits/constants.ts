/**
 * 统一数值范围（前后端口径一致）。
 * Shell 侧对应：`module/bin/lib/switch_prelude.sh`、`power_saver_core.sh` 的 qsc_clamp_*；
 * 改这里时请同步改 shell 注释里的同名范围。
 */
export const LIMITS = {
  levelMin: 1,
  levelMax: 100,
  levelOff: 110,
  powerStopTimeMin: 1,
  powerStopTimeMax: 120,
  tempSwitchMin: 25,
  tempSwitchMax: 70,
  currentTempMin: 25,
  currentTempMax: 60,
  safetyTempMin: 40,
  safetyTempMax: 55,
  /** 充满再停等待秒数（与 shell charge_full_wait_sec 一致） */
  chargeFullWaitMin: 60,
  chargeFullWaitMax: 3600,
  /** 微安：0.1A–10A */
  uaMin: 100_000,
  uaMax: 10_000_000,
  /** 二限/游戏等小电流上限 3A */
  uaSmallMax: 3_000_000,
  appListMax: 64,
  scheduleMax: 16,
  pathListMax: 32,
  reaffirmSecMin: 0,
  reaffirmSecMax: 300,
  driftUaMin: 0,
  driftUaMax: 2_000_000,
  stepUaMin: 0,
  stepUaMax: 2_000_000,
};
