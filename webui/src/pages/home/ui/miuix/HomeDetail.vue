<script setup lang="ts">
import { useAppStore } from "@/stores";

const store = useAppStore();
</script>

<template>
  <section class="miuix-card miuix-detail">
    <div class="miuix-detail__row">
      <span>电压</span>
      <b>{{ store.status.voltage }} V</b>
    </div>
    <div class="miuix-detail__row">
      <span>版本</span>
      <b>{{ store.status.version }}</b>
    </div>
  </section>
</template>

<style scoped lang="scss">
.miuix-detail {
  padding: 4px 0;
}

.miuix-detail__row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 13px 14px;
  font-size: 15px;
  border-bottom: 1px solid var(--qsc-hairline);

  &:last-child {
    border-bottom: none;
  }

  span {
    color: var(--qsc-text);
  }

  b {
    font-weight: 550;
    color: var(--qsc-text-2);
  }
}
</style>
