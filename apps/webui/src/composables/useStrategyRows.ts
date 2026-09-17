import { computed } from "vue";
import { STRATEGY_ROWS, type StrategyPlanKey } from "@/shared/config/strategy";
import { useAppStore } from "@/stores";

export function useStrategyRows() {
  const store = useAppStore();
  return computed(() => {
    const plans: Record<StrategyPlanKey, string> = {
      powerPlan: store.powerPlan,
      tempPlan: store.tempPlan,
      fullPlan: store.fullPlan,
      compatPlan: store.compatPlan,
      currentPlan: store.currentPlan,
    };
    return STRATEGY_ROWS.filter(
      (row) => !row.requireCurrentFeature || store.currentFeature,
    ).map((row) => ({
      id: row.id,
      label: row.label,
      value: plans[row.plan],
    }));
  });
}
