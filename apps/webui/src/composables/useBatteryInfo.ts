import { computed } from "vue";
import {
  capacityRetention,
  formatMah,
  healthLabel,
  isChargingLabel,
  parsePercent,
} from "@/shared/lib/batteryDisplay";
import { BadgeType } from "@/shared";
import { useAppStore } from "@/stores";

function badgeType(t: string): BadgeType {
  if (
    t === BadgeType.Success ||
    t === BadgeType.Warning ||
    t === BadgeType.Danger ||
    t === BadgeType.Primary
  ) {
    return t;
  }
  return BadgeType.Primary;
}

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

  const statusBadgeType = computed(() => badgeType(store.status.badgeType));

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
