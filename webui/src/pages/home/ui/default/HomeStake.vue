<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import { useBatteryInfo } from "@/composables";
import { useAppStore } from "@/stores";

const store = useAppStore();
const { healthText, designMahText, fullMahText, sohText } = useBatteryInfo();
</script>

<template>
  <SectionHead title="电池本钱" hint="健康与容量，心里有数" />
  <section class="card stake-card">
    <div class="mini-grid">
      <div class="mini">
        <div class="mv">{{ healthText }}</div>
        <div class="ml">健康</div>
      </div>
      <div class="mini">
        <div class="mv">{{ sohText }}</div>
        <div class="ml">还剩几成</div>
      </div>
      <div class="mini">
        <div class="mv">{{ fullMahText }}</div>
        <div class="ml">满充容量</div>
      </div>
      <div class="mini">
        <div class="mv">{{ designMahText }}</div>
        <div class="ml">出厂容量</div>
      </div>
      <div class="mini mini--wide">
        <div class="mv">{{ store.status.cycleCount }}</div>
        <div class="ml">已循环</div>
      </div>
    </div>
  </section>
</template>

<style scoped lang="scss">
.mini-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  padding: 16px;
}

.stake-card .mini--wide {
  grid-column: 1 / -1;
}

.mini .mv {
  font-size: 18px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}

.mini .ml {
  font-size: 11px;
  color: var(--qsc-text-3);
  margin-top: 2px;
}
</style>
