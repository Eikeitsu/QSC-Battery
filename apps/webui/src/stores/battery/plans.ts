import { computed, type Ref } from "vue";
import { BinaryFlag, type CurrentConfig, type Settings } from "@/shared";

export function createBatteryPlans(
  settings: Settings,
  current: CurrentConfig,
  currentFeature: Ref<boolean>,
) {
  const powerPlan = computed(() => {
    const stop = settings.power_stop;
    const start = settings.power_start;
    if (String(stop) === "110") return "已关闭";
    return `停充 ≥${stop}% · 恢复 ≤${start}%`;
  });

  const tempPlan = computed(() => {
    if (settings.temperature_switch === BinaryFlag.Off) return "已关闭";
    return `停充 ≥${settings.temperature_switch_stop}°C · 恢复 ≤${settings.temperature_switch_start}°C`;
  });

  const currentPlan = computed(() => {
    if (!currentFeature.value) return "--";
    if (!Number(current.current_control)) return "已关闭";
    const parts = ["已开启"];
    if (Number(current.bypass_enable)) {
      if (Number(current.battery_stop) <= 100)
        parts.push(`旁路≥${current.battery_stop}%`);
      if (Number(current.bypass_temp) <= 100) parts.push(`旁路≥${current.bypass_temp}°C`);
      if ((current.bypass_schedule || []).length) parts.push("旁路时段");
    }
    if (Number(current.slow_charge) <= 100) parts.push(`慢充≥${current.slow_charge}%`);
    if (Number(current.temperature_current)) parts.push("温控限流");
    if (Number(current.app_limit)) parts.push("游戏限流");
    return parts.join(" · ");
  });

  const fullPlan = computed(() =>
    settings.charge_full === BinaryFlag.On ? "已开启" : "已关闭",
  );
  const resetPlan = computed(() =>
    settings.power_reset === BinaryFlag.On ? "已开启" : "已关闭",
  );
  const compatPlan = computed(() =>
    settings.compatibility_mode === BinaryFlag.On ? "已开启" : "已关闭",
  );

  return {
    powerPlan,
    tempPlan,
    currentPlan,
    fullPlan,
    resetPlan,
    compatPlan,
  };
}
