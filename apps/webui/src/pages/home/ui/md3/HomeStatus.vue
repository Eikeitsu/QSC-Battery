<script setup lang="ts">
import ThemeSwitch from "@/shared/ui/ThemeSwitch.vue";
import { useAppStore } from "@/stores";

const store = useAppStore();
</script>

<template>
  <section class="md3-tonal md3-status">
    <div class="md3-status__main">
      <div class="md3-status__icon" aria-hidden="true">⚡</div>
      <div class="md3-status__text">
        <div class="md3-status__title">{{ store.status.badge }}</div>
        <div class="md3-status__summary">{{ store.status.desc }}</div>
        <div class="md3-status__meta">{{ store.status.updatedAt }}</div>
      </div>
    </div>
    <div class="md3-status__switch">
      <span class="md3-status__switch-label">模块总开关</span>
      <ThemeSwitch
        :model-value="store.status.moduleOn"
        @update:model-value="store.toggleModule"
      />
    </div>
  </section>
</template>

<style scoped lang="scss">
.md3-status {
  padding: 16px 18px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.md3-status__main {
  display: flex;
  gap: 14px;
  align-items: flex-start;
}

.md3-status__icon {
  width: 40px;
  height: 40px;
  border-radius: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: color-mix(in srgb, var(--qsc-primary) 18%, transparent);
  flex-shrink: 0;
  font-size: 18px;
}

.md3-status__title {
  font-size: 17px;
  font-weight: 600;
  line-height: 1.25;
}

.md3-status__summary {
  margin-top: 4px;
  font-size: 13px;
  color: var(--qsc-text-2);
  line-height: 1.45;
}

.md3-status__meta {
  margin-top: 6px;
  font-size: 12px;
  color: var(--qsc-text-3);
  font-variant-numeric: tabular-nums;
}

.md3-status__switch {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding-top: 4px;
  border-top: 1px solid color-mix(in srgb, var(--qsc-primary) 12%, transparent);
}

.md3-status__switch-label {
  font-size: 14px;
  font-weight: 500;
}
</style>
