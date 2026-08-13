<script setup lang="ts">
import SectionHead from "@/shared/ui/SectionHead.vue";
import type { LogEntry } from "@/shared";
import { useAppStore } from "@/stores";
import LogFilter from "./LogFilter.vue";
import LogLines from "./LogLines.vue";

defineProps<{
  lines: LogEntry[];
  levelFilter: string;
  filterActive: boolean;
}>();

defineEmits<{
  refresh: [];
  clear: [];
  "update:levelFilter": [v: string];
}>();

const store = useAppStore();
</script>

<template>
  <SectionHead title="运行日志" hint="模块触发停充 / 恢复时写入" />
  <section class="card meta">
    <div class="row">
      <span>最近 {{ store.logLines }} 行</span>
      <span>{{ store.logSize }}</span>
    </div>
    <LogFilter
      :model-value="levelFilter"
      @update:model-value="$emit('update:levelFilter', $event)"
    />
    <div class="actions">
      <van-button size="small" type="primary" plain @click="$emit('refresh')">
        刷新
      </van-button>
      <van-button size="small" type="danger" plain @click="$emit('clear')">
        清空
      </van-button>
    </div>
  </section>
  <section class="card log-card">
    <LogLines :lines="lines" :filtered="filterActive" />
  </section>
</template>

<style scoped lang="scss">
.meta {
  padding: 14px 16px;
  margin-bottom: 12px;
}

.row {
  display: flex;
  justify-content: space-between;
  font-size: 13px;
  color: var(--qsc-text-2);
  margin-bottom: 4px;
}

.actions {
  display: flex;
  gap: 8px;
}

.log-card {
  padding: 14px;
  background: var(--qsc-surface-2);
}
</style>
