<script setup lang="ts">
import ThemeSwitch from "@/shared/ui/ThemeSwitch.vue";
import { useAppStore } from "@/stores";

const store = useAppStore();
</script>

<template>
  <section class="miuix-card miuix-overview">
    <div class="miuix-overview__status">
      <div>
        <div class="miuix-overview__badge">{{ store.status.badge }}</div>
        <div class="miuix-overview__desc">{{ store.status.desc }}</div>
        <div class="miuix-overview__time">{{ store.status.updatedAt }}</div>
      </div>
      <ThemeSwitch
        :model-value="store.status.moduleOn"
        @update:model-value="store.toggleModule"
      />
    </div>

    <div class="miuix-inset-grid">
      <div class="miuix-inset">
        <div class="miuix-inset__v">{{ store.status.level }}%</div>
        <div class="miuix-inset__l">电量</div>
      </div>
      <div class="miuix-inset">
        <div class="miuix-inset__v">{{ store.status.temp }}°</div>
        <div class="miuix-inset__l">温度</div>
      </div>
      <div class="miuix-inset">
        <div class="miuix-inset__v">{{ store.status.chargeLabel }}</div>
        <div class="miuix-inset__l">充电</div>
      </div>
      <div class="miuix-inset">
        <div class="miuix-inset__v">{{ store.status.currentMa }}</div>
        <div class="miuix-inset__l">电流 mA</div>
      </div>
    </div>
  </section>
</template>

<style scoped lang="scss">
.miuix-overview {
  padding: 14px 12px 12px;
}

.miuix-overview__status {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  padding: 2px 4px 14px;
}

.miuix-overview__badge {
  font-size: 17px;
  font-weight: 600;
}

.miuix-overview__desc {
  margin-top: 4px;
  font-size: 12px;
  color: var(--qsc-text-2);
  line-height: 1.4;
  max-width: 70vw;
}

.miuix-overview__time {
  margin-top: 4px;
  font-size: 11px;
  color: var(--qsc-text-3);
}

.miuix-inset-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.miuix-inset {
  background: var(--qsc-surface-2);
  border-radius: 12px;
  padding: 12px 10px;
}

.miuix-inset__v {
  font-size: 16px;
  font-weight: 650;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.miuix-inset__l {
  margin-top: 2px;
  font-size: 11px;
  color: var(--qsc-text-3);
}
</style>
