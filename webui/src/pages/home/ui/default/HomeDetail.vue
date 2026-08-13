<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import { useAppStore } from "@/stores";

const store = useAppStore();
</script>

<template>
  <SectionHead title="运行详情" />
  <section class="card">
    <div class="mini-grid">
      <div class="mini">
        <div class="mv">{{ store.status.chargeLabel }}</div>
        <div class="ml">充电状态</div>
      </div>
      <div class="mini">
        <div class="mv">{{ store.status.voltage }}</div>
        <div class="ml">电压 V</div>
      </div>
      <div class="mini">
        <div class="mv">{{ store.status.currentMa }}</div>
        <div class="ml">电流 mA</div>
      </div>
      <div class="mini">
        <div class="mv">{{ store.status.version }}</div>
        <div class="ml">版本</div>
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
