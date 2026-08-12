import { computed } from "vue";
import {
  capacityRetention,
  formatMah,
  healthLabel,
  isChargingLabel,
  parsePercent,
} from "@/shared/lib/batteryDisplay";
import type { BadgeType } from "@/shared/types";
import { useAppStore } from "@/stores";

export function useBatteryInfo() {
  const store = useAppStore();

  const charging = computed(() => isChargingLabel(store.status.chargeLabel));
  const healthText = computed(() => healthLabel(store.status.health));
  const designMahText = computed(() => formatMah(store.status.designMah));
  const fullMahText = computed(() => formatMah(store.status.fullMah));

  const soh = computed(() => parsePercent(store.status.soh));
  const sohText = computed(() => (soh.value !== null ? `${soh.value}%` : "--"));
  const retention = computed(() =>
    capacityRetention(store.status.fullMah, store.status.designMah),
  );
  const barPct = computed(() => soh.value ?? retention.value ?? 0);
  const hasBar = computed(() => soh.value !== null || retention.value !== null);

  function badgeType(t: string): "primary" | "success" | "warning" | "danger" {
    if (t === "success" || t === "warning" || t === "danger" || t === "primary") {
      return t;
    }
    return "primary";
  }

  const statusBadgeType = computed(() => badgeType(store.status.badgeType as BadgeType));

  return {
    store,
    charging,
    healthText,
    designMahText,
    fullMahText,
    soh,
    sohText,
    retention,
    barPct,
    hasBar,
    badgeType,
    statusBadgeType,
  };
}
