/** 统一数值范围（前后端口径一致） */
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
