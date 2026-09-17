export const STRATEGY_ROW_IDS = {
  Power: "power",
  Temp: "temp",
  Full: "full",
  Compat: "compat",
  Current: "current",
} as const;

export type StrategyPlanKey =
  "powerPlan" | "tempPlan" | "fullPlan" | "compatPlan" | "currentPlan";

export interface StrategyRowDef {
  id: string;
  label: string;
  plan: StrategyPlanKey;
  requireCurrentFeature?: boolean;
}

export const STRATEGY_ROWS: readonly StrategyRowDef[] = [
  { id: STRATEGY_ROW_IDS.Power, label: "电量停充", plan: "powerPlan" },
  { id: STRATEGY_ROW_IDS.Temp, label: "温控停充", plan: "tempPlan" },
  { id: STRATEGY_ROW_IDS.Full, label: "充满再停", plan: "fullPlan" },
  { id: STRATEGY_ROW_IDS.Compat, label: "兼容模式", plan: "compatPlan" },
  {
    id: STRATEGY_ROW_IDS.Current,
    label: "电流控制",
    plan: "currentPlan",
    requireCurrentFeature: true,
  },
];
